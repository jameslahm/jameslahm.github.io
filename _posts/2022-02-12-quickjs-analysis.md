---
title: QuickJs 剖析
date: 2022-02-12
description:
tags: [compiler, vm]
author: Jameslahm
key: quickjs-analysis
---



## Value 表示
在动态语言的VM中，由于通常变量的值都不是静态类型的，都是可变的，另一方面动态类型的值一般涉及到Gc的设计实现，因此不能直接使用特定类型来直接表示值，而一般抽象出一层Value来统一表示所有的值，即这个Value有可能为null，有可能为undefined，有可能为number，那么就需要将不同值来编码到另一个通用表示，简单来说是一个映射关系。通常的编码方式包括Tagged Value和Nan Boxing，Tagged Value跟union类似，我们在不知道值的情况下，可以加个tag解决，读取值时，先读取tag，再根据tag拿到对应的有意义的值，这种方法很简单，但是需要多一个字长来存储tag，通常64位对齐的情况下，就需要64位来存储tag，这样很浪费内存，当然也有类似Tagged Pointer的hack方法，利用指针LSB来存储一些信息（如v8中small integer的表示）。Nan boxing则是另一种编码方式，不依赖显示的tag，而是将所有信息都编码到一个64位的浮点数中，一般使用quiet nan剩下的可用编码位来存储信息，比如一个浮点数，64位，1位用来存储sign，11位用来存储exponent，52位用来存储magnitude，Quiet Nan的表示为11位全为1，52位的首位是1，那么还剩52位可以用来编码信息，比如可以一部分位用来存放tag，另一部分位用来存放除了浮点数的value的值，由于一般64位机器上指针只会用到48位，所以存储指针也是够用的，当然在jscore中还有shift的优化，即给所有的编码统一加一个偏移量，使得ptr的剩余16位全为0，这样可以大大加快指针读取的速度。


qjs中会使用不同的编码方式，因此操纵value时一定要使用定义好的宏，这里以Tagged Value为例
```cpp
typedef union JSValueUnion {
    int32_t int32;
    double float64;
    void *ptr;
} JSValueUnion;

typedef struct JSValue {
    JSValueUnion u;
    int64_t tag;
} JSValue;

enum {
    JS_TAG_SYMBOL      = -8,
    JS_TAG_STRING      = -7,
    JS_TAG_MODULE      = -3, /* used internally */
    JS_TAG_FUNCTION_BYTECODE = -2, /* used internally */
    JS_TAG_OBJECT      = -1,

    JS_TAG_INT         = 0,
    JS_TAG_BOOL        = 1,
    JS_TAG_NULL        = 2,
    JS_TAG_UNDEFINED   = 3,
    JS_TAG_UNINITIALIZED = 4,
    JS_TAG_CATCH_OFFSET = 5,
    JS_TAG_EXCEPTION   = 6,
    JS_TAG_FLOAT64     = 7,
};
```

tag的设计用于区分不同类型的值即可，比如这里也可以为Bool增加True和False的tag，这样不用读取实际值，会更快，这里quickjs中关于tag还有一个小细节，即所有带Ref的tag都是负数，这样可以快速判断是否需要dup等。Primitive类型的值，如int，bool，float等，直接读取union中的值即可，对于string，symbol来讲，则会使用ptr指向JSString，JSString中存储对应的字符串或Symbol的值，剩下最重要的就是JsObject了，JsObject即类似Js中Object的引用类型，JsObject中需要存储prototype来支持Js基于原型链的继承方式，同时需要支持属性的增，删，改，查（当然也需要支持prototype的链式查找），同时JsObject作为Function，Array，Number，String，Regexp等类型的基础载体，需要支持存放额外数据，如Number的数值，Regexp的正则表达式等。JSObject的大致结构如下，prop用于存储所有的属性，shape中会存储对应的prototype，u中会存放实际额外的数据。
```cpp
typedef struct JSObject {
    /* byte offsets: 16/24 */
    JSShape *shape; /* prototype and property names + flag */
    JSProperty *prop; /* array of properties */
    /* byte offsets: 28/48 */
    union {
        struct { /* JS_CLASS_C_FUNCTION: 12/20 bytes */
            JSContext *realm;
            JSCFunctionType c_function;
            uint8_t length;
            uint8_t cproto;
            int16_t magic;
        } cfunc;
        JSRegExp regexp;    /* JS_CLASS_REGEXP: 8/16 bytes */
        JSValue object_data;    /* for JS_SetObjectData(): 8/16/16 bytes */
    } u;

}
```

JSShape的结构如下，其主要用于存储JSObject中的属性名对应的prop中的索引
```cpp
struct JSShape {
    uint32_t prop_hash_mask;
    int prop_size; /* allocated properties */
    int prop_count; /* include deleted properties */
    int deleted_prop_count;
    JSObject *proto;
    JSShapeProperty prop[0]; /* prop_size elements */
};

typedef struct JSShapeProperty {
    uint32_t hash_next : 26; /* 0 if last in list */
    uint32_t flags : 6;   /* JS_PROP_XXX */
    JSAtom atom; /* JS_ATOM_NULL = free property entry */
} JSShapeProperty;
```

JSShape中使用动态哈希表实现prop的存储，JSShapeProperty中存放属性名及对应的flag（configurable，writable，enumerable等），查属性的大致过程如下
```cpp
h = (uintptr_t)atom & sh->prop_hash_mask;
while (h) {
    pr = &prop[h - 1];
    if (likely(pr->atom == atom)) {
        *ppr = &p->prop[h - 1];
        /* the compiler should be able to assume that pr != NULL here */
        return pr;
    }
    h = pr->hash_next;
}
```

由于会存在hash冲突，每次检查name是否一致，若不一致，则查找下一个对应相同hash的属性，查找到后，即返回JSObject中prop数组的索引，拿到索引后即可拿到实际属性的值。增加属性时，即先在JSShape中增加属性，再到JSObject中增加对应的prop即可，设置属性时，按照原型链的顺序，依次在JSShape中查找对应的属性名，若找到后，直接修改对应JSObject中的value即可，删除属性时，直接在JSShape的动态哈希表中删除，再删除JSObject中的值即可。这里的JSShape类似于v8中的hidden map，都是用于优化当存在大量对象的属性名相同时对象的属性查找问题，比如如果有大量对象的属性名完全一致，这样就可以多个对象共用一个JSShape，同时也可以使用Inline Cache进行优化，当检查到对象的Shape一致时，就可以使用已经缓存的属性索引直接查找到JSObject中的值。当然，JSObject是易变的，由于Object可以任意增删属性，这会导致原本一样Shape的对象不能共用一个Shape。quickjs中采用hash的方式来管理JSShape，简单来说，hash的JSShape是可以共用的，不hash的JSShape是不可以共用的，当一个对象首次创建时，会先在可hash的JSShape池中查找是否有跟当前对象的prototype一样且属性个数为0的JSShape，如果有则会直接复用该JSShape，若没有则新建一个，当给对象增加属性时，会先检查当前JSShape的hash值，如果是不hash的，则直接修改即可，如果是hash的，且当前只有这一个对象在使用这个JSShape，那么也可以直接改当前JSShape，如果有多个，那么必须先clone该JSShape之后，再进行修改，这里quickjs对增加属性有一个简单的transition规则，即首先会查找当前hash的JSShape池里是否有刚好比当前JSShape多一个要增加属性的JSShape，如果有，则直接使用该JSShape。当删除属性时，跟增加属性类似，quickjs中会对被删除的属性先留空，当发现删除过多属性时，会对prop进行压缩，回收使用的空间。quickjs当前使用JSShape时不会对constructor进行优化，以下面为例
```cpp
function Point(){
    this.x = 1;
    this.y = 2;
}
```

第一次创建时，quickjs会创建一个空的JSShape，接着由于只有该对象会使用这个JSShape，后面添加x，y时会直接在该JSShape上进行修改，这就导致下次再次调用Point函数时，无法找到空的JSShape，而必须创建一个，当添加x属性时也是，只有添加y属性时可以复用JSShape。JSObject同时还需承载其他类型的值数据，比如Function，Regexp，quickjs中使用class_id来存储当前Object实际的数据类型，这样可以根据class_id来获取对应的value，以Function（Native）为例，
```cpp
JSValue func_obj;
JSObject *p;
func_obj = JS_NewObjectProtoClass(ctx, proto_val, JS_CLASS_C_FUNCTION);
p = JS_VALUE_GET_OBJ(func_obj);
p->u.cfunc.c_function.generic = func;
```

这里在u中直接存放func的指针，再以Number为例，在u的object_data中存放实际Primitive的值，Stirng，Symbol等与此类似
```cpp
if (JS_VALUE_GET_TAG(obj) == JS_TAG_OBJECT) {
    p = JS_VALUE_GET_OBJ(obj);
    switch(p->class_id) {
    case JS_CLASS_NUMBER:
    case JS_CLASS_STRING:
    case JS_CLASS_BOOLEAN:
    case JS_CLASS_SYMBOL:
    case JS_CLASS_DATE:
        JS_FreeValue(ctx, p->u.object_data);
        p->u.object_data = val;
        return 0;
    }
}
```

## Parse流程
一般对于VM来讲，源代码语言需经过lexer，parser，compiler，interpreter几个阶段，最终执行。lexer解析源代码获取token流，parser获取token流解析为AST，compiler获取AST编译为字节码，interpreter获取字节码执行，一般来讲，lexer和parser是编译流水线中较简单的部分。当然这几个阶段并不一定是严格串行的，也不是严格独立的，比如quickjs中lexer，parser，compiler是在一遍解析中完成的，即在单遍pass中就完成了由字符流到字节码流。

### Lexer实现
lexer的主要任务是读取字符流，转为token流，token流则是后续解析中可识别的最小单元，通常token包括各种运算符，变量名，关键字等。在解析时，依次读取每个字符，根据字符判断返回token即可，quickjs中lexer主要实现在next_token函数。当然lexer中也有许多优化，如 https://v8.dev/blog/scanner。以quickjs中token定义为例，主要分为四种，包括TOK_NUMBER，TOK_STRING这种带value的token，比如number和string的literal，需要在token中存储literal的值，以及TOK_LT等运算符，以及TOK_CLASS等关键词，当然最后还包括EOF，表示字符流结束。

### Atom实现
由于在parse过程中会出现大量重复的字符串，比如变量名会重复使用，各种关键词会重复出现，如果在token中直接存储对应的字符串值，比如直接在TOK_IDENT中存储变量名，这样会造成大量的空间浪费，在比较时也很费时间，因此一般会采用类似符号表的做法，将相同字符串存储在一起，用一个唯一ID表示即可，quickjs中即用atom来代表这种表示某个字符串的唯一ID。此外，Atom还会使用MSB区分是否为number。
```cpp
static LEPUSAtom LEPUS_NewAtomStr(LEPUSContext *ctx, LEPUSString *p) {
  LEPUSRuntime *rt = ctx->rt;
  uint32_t n;
  if (is_num_string(&n, p)) {
    if (n <= LEPUS_ATOM_MAX_INT) {
      lepus_free_string(rt, p);
      return __JS_AtomFromUInt32(n);
    }
  }
  return __JS_NewAtom(rt, p, LEPUS_ATOM_TYPE_STRING);
}
```


### Parse算法
一般对于Parse主要有LL和LR两类解析算法，主要是通过CFG来进行归约或推导。quickjs中主要采用LL加pratt parser的方法进行解析。https://en.wikipedia.org/wiki/Operator-precedence_parser

以Eval为例，在解析时是作为一个function的，由js_parse_program进入后，首先js_parse_directives，主要用来解析'use strict'这种directive指令，接着parse_source_element，即依次解析合法的语句，在parse_source_element中，parse_function_decl负责解析function定义，parse_export负责解析export语句，parse_import负责解析import语句，parse_statement_or_decl则用于解析各种statement和declaration。
```cpp
static __exception int lepus_parse_source_element(LEPUSParseState *s) {
  if (s->token.val == TOK_FUNCTION ||
      (token_is_pseudo_keyword(s, LEPUS_ATOM_async) &&
       peek_token(s, TRUE) == TOK_FUNCTION)) {
    if (lepus_parse_function_decl(s, LEPUS_PARSE_FUNC_STATEMENT,
                                  LEPUS_FUNC_NORMAL, LEPUS_ATOM_NULL,
                                  s->token.ptr, s->token.line_num))
      return -1;
  } else if (s->token.val == TOK_EXPORT && fd->module) {
    if (lepus_parse_export(s)) return -1;
  } else if (s->token.val == TOK_IMPORT && fd->module &&
             peek_token(s, FALSE) != '(') {
    if (lepus_parse_import(s)) return -1;
  } else {
    if (lepus_parse_statement_or_decl(s, DECL_MASK_ALL)) return -1;
  }
  return 0;
}
```

在parse_function_decl中，先parse_argument后，之后依旧parse_source_element，对于statement类的function declaration，由于不受重定义的影响，quickjs未对其进行redeclaration的检查，当然这也是qjs现有的一个bug，比如下面，qjs会编译通过，实际上应该为sayHello Syntax Error
```cpp
let sayHello = 1;

function sayHello(){}
```

在parse_statement_or_decl中，根据当前token，进行对应的语句解析即可，以throw为例
```cpp
case TOK_THROW:
    if (next_token(s))
        goto fail;
    if (js_parse_expr(s))
        goto fail;
    break;
```

在变量声明中，主要有三种情况，const，let和var（当然还包括catch）。变量声明统一在parse_var中处理，声明解析主要分为三步，一是判断变量类型，以进行对应的scope检查，二是获取变量名并预定义变量，三是解析初始值表达式。Function中存储变量结构如下
```cpp
typedef struct JSFunctionDef {
    JSVarDef *vars;
    int scope_first; /* index into vd->vars of first lexically scoped variable */
    int scope_level; /* index into fd->scopes if the current lexical scope */
    JSVarScope *scopes;
}

typedef struct JSVarScope {
    int parent;  /* index into fd->scopes of the enclosing scope */
    int first;   /* index into fd->vars of the last variable in this scope */
} JSVarScope;
```

scopes是包含所有scope的数组，简单来说，每个scope中有对应parent scope的index，以及最后一个该scope中的变量index，而function中存储当前scope的索引及当前scope对应的第一个（其实是最后一个lexically scoped的变量），lexically scoped指得就是let和const声明的变量，对于var声明的变量，由于声明提升会做hoist处理。对于let和const声明的变量，首先会使用find_lexical_decl查找在当前scope是否存在相同命名的lexically的变量，大致查找过程如下
```cpp
while (scope_idx >= 0) {
    JSVarDef *vd = &fd->vars[scope_idx];
    if (vd->var_name == name && vd->is_lexical))
        return scope_idx;
    scope_idx = vd->scope_next;
}
```

由于lexically的查找有GLOBAL_VAR_OFFSET限制，理论上单个函数的local variable数量是不能超过0x40000000个的，如果没有再接着看是否和function的argument有冲突
```cpp
for(i = fd->arg_count; i-- > 0;) {
    if (fd->args[i].var_name == name)
        return i | ARGUMENT_VAR_OFFSET;
}
```

如果没有，再接着看是否跟hoist的var声明的变量有冲突，scope_level为0即代表是var声明的变量，is_child_scope即判断var声明的是否在当前scope的子scope中
```cpp
for(i = 0; i < fd->var_count; i++) {
    JSVarDef *vd = &fd->vars[i];
    if (vd->var_name == name && vd->scope_level == 0) {
        if (is_child_scope(ctx, fd, vd->scope_next,
                           scope_level))
            return i;
    }
}
```

这些检查都没有问题后，即可加入到当前function的变量列表中，idx即为vars的索引，同时会更新对应scope的最新的lexically的变量索引
```cpp
int idx = add_var(ctx, fd, name);
if (idx >= 0) {
    JSVarDef *vd = &fd->vars[idx];
    vd->var_kind = var_kind;
    vd->scope_level = fd->scope_level;
    vd->scope_next = fd->scope_first;
    fd->scopes[fd->scope_level].first = idx;
    fd->scope_first = idx;
}
```

而对于var声明的变量，首先也会find_lexical_decl检查是否有重名的lexically的variable，接着会find_var检查是否有重名的var声明的以及函数参数的变量，这里如果有则会直接返回，并不会抛出Syntax error，如果没有则直接add_var加入到变量列表中。除了上述情况下，还有一种特殊情况需要处理，那就是全局变量，全局是作为一个function进行编译的，在global中定义的变量也就是全局变量，对于全局变量同样会进行上述的scope检查，不过会用JsGlobalVar统一管理，在执行enter_scope时统一初始化。此外，对于global的变量，qjs在lookup时会使用名字进行查询，而对于function内部的local variable，则会使用直接使用opcode后面的index直接索引对应的变量，所以一般情况下，多在function内使用局部变量也比全局变量要快，同时qjs内部还对前几个局部变量做了优化，直接使用特定的opcode来索引对应的局部变量，目前支持前4个局部变量的直接索引，即不用读取对应的index。
除了declaration之外，剩下的就是statement。statement中比较重要的是branch以及expr的解析，branch一般包括for循环，while循环，if判断，这些都可以使用LL直接解析，而对于expr，由于有很多运算符，且有优先级限制，当然也可以使用LL强制优先级进行解析，但这样会比较麻烦，一般可采用operator precedence的解析方法，大致思路如下
```cpp
SN Parser::ParseBinaryExpression(SN left, int precedence)
{
  while (1)
  {
    if (CheckIsBianryOp(lexer_->current_token()))
    {
      auto op = GetBinaryOpFromToken(lexer_->current_token());
      auto next_precedence = GetBinaryOpPrecedence(op);
      if (next_precedence <= precedence)
      {
        return left;
      }
      else
      {
        lexer_->GetToken();
        auto next_left = ParseUnaryExpression();
        auto next_right =
            ParseBinaryExpression(move(next_left), next_precedence);
        left =
            make_shared<BinaryExpressionNode>(op, move(left), move(next_right));
      }
    }
    else
    {
      return left;
    }
  }
}
```

在每次进入解析binary表达式前，都会带一个当前operator的优先级，解析时先判断是否为一个合法的binary op，如果是则拿到operator对应的优先级后，判断这个优先级是否大于解析进来时传递的优先级，如果不大于，则说明当前operator的优先级并不比前一个高，这个时候就可以按照从左至右的顺序进行解析，直接返回即可，如果优先级更高，则可以与前一个先结合，这样就保证优先级的规则，比如1+1+1\*2，在第一次解析到第二个+时，会直接返回，那么1+1就会结合在一起，接着第二次解析到\*时，由于优先级更高，则1\*2会结合在一起，最后（1+1）和（1*2）再结合到一起。qjs中解析表达式依次是parse_expr，parse_assign_expr，parse_cond_expr，parse_coalesce_expr，parse_logical_and_or，parse_expr_binary，在bianry_expr前是按照优先级顺序组织的，在binary_expr中则使用到level来判断优先级，level越小，优先级越高
```cpp
static __exception int js_parse_expr_binary(JSParseState *s, int level,
                                            int parse_flags)
{
    int op, opcode;

    if (level == 0) {
        return js_parse_unary(s, (parse_flags & PF_ARROW_FUNC) |
                              PF_POW_ALLOWED);
    }
    if (js_parse_expr_binary(s, level - 1, parse_flags))
        return -1;
    for(;;) {
        op = s->token.val;
        switch(level) {
        case 1:
            switch(op) {
            case '*':
                opcode = OP_mul;
                break;
            }
            break;
        case 2:
            switch(op) {
            case '+':
                opcode = OP_add;
                break;
            }
            break;
        }
        if (next_token(s))
            return -1;
        if (js_parse_expr_binary(s, level - 1, parse_flags & ~PF_ARROW_FUNC))
            return -1;
        emit_op(s, opcode);
     }
}
```

当然，这里也有可以优化的地方，由于在解析表达式时会有大量的递归调用，这会造成不小的开销，可以尝试改写为循环。

Reference
- https://en.wikipedia.org/wiki/Operator-precedence_parser
- https://v8.dev/blog/preparser
- https://v8.dev/blog/scanner
- https://github.com/jameslahm/yajp


## Bytecode Compiler
这里的Compiler主要是指Bytecode Compiler，即在quickjs单遍parse中直接生成的bytecode。bytecode作为一种IR，起着承上启下的作用，承上作为比AST更low level的中间表示，可以交给interpreter执行，由于其良好的local性和小空间，效率比AST执行更快，启下作为native code的输入流，可以在bytecod级别做优化，生成更好的机器码。bytecode主要分为两类，对应两类不同的VM，分别是Stack based和Register based，stack based的特点是所有的操作数都是基于栈的，比如add的opcode，在执行时会默认从栈中弹出两个数，加完之后在push回去。register based的特点则是基于寄存器的，比如在add的opcode中，后面会指定两个寄存器用于做运算。Stack based的bytecode实现起来较为容易，但有频繁访问栈的缺点，比如有给栈加一个acc的寄存器的优化，这样每次可少读一次栈，而register based实现起来比stack based的更为困难，还需涉及到寄存器分配等操作。quickjs中采用的则是基于stack的bytecode。

### 字节码设计
Quickjs中所有的字节码都在quickjs-opcode.h这个文件中，opcode主要分为三类，一类是基础使用的字节码，这部分字节码在编译及最终执行中都会用到，另一类是临时opcode，这类会在编译完后解析或者优化的过程中被替换掉或删掉，最后一类是short opcode的优化，quickjs中是默认开启的，针对部分opcode进行相应的优化，比如push_i32是push一个32位的值，当这个常量在8位内时，既可以直接使用push_i8代替，这样原本字节码后面需要32位现在只需要8位代替，大大缩小字节码占用空间。

### 字节码语义
字节码需要能够完全替代AST，在interpreter下能表示所有program的semantic，主要的语义有以下几类
- branch，包括if，for，while等需要分支判断，跳转的语句
- operator，运算符，主要用于各种表达式计算
- push，push进栈各种值，包括常量值，属性名值，JSValue等
- call，主要用于函数调用
- throw，主要用于抛出异常及错误处理
- var，主要用于获取，修改局部变量，全局变量等
- field，主要是用于获取，修改对象属性
下面简单介绍一下各个opcode的语义
- OP_push_i32
向栈中push一个32位的值
- OP_push_const
向栈中push一个常量池中的值
- OP_push_minus1
向栈中push一个-1
- OP_push_0
向栈中push一个0
- OP_push_1
向栈中push一个1
- OP_push_2
向栈中push一个2
- OP_push_3
向栈中push一个3
- OP_push_4
向栈中push一个4
- OP_push_5
向栈中push一个5
- OP_push_6
向栈中push一个6
- OP_push_7
向栈中push一个7
- OP_push_i8
向栈中push一个8位整数
- OP_push_i16
向栈中push一个16位整数
- OP_push_const8
向栈中push一个常量，该常量索引为8位整数
- OP_fclosure8
向栈中push一个闭包对象，该常量索引位8位整数
- OP_push_empty_string
向栈中push一个空串
- OP_get_length
获取对象的length属性
- OP_push_atom_value
向栈中push atom代表的JSValue
- OP_undefined
向栈中push一个undefined值
- OP_null
向栈中push一个null值
- OP_push_this
向栈中push this当前的值
- OP_push_false
向栈中push一个false
- OP_push_true
向栈中push一个true
- OP_object
向栈中push一个新创建的object
- OP_special_object
- OP_rest
- OP_drop
删除栈顶上的值
- OP_nip
删除栈顶第二个值
- OP_nip1
删除栈顶第三个值
- OP_dup
复制栈顶的值
- OP_dup2
复制栈顶的前两个值
- OP_dup3
复制栈顶的前三个值
- OP_dup1
复制栈顶的第二个值
- OP_insert2
复制栈顶值并插入到栈顶第三个位置
- OP_insert3
复制栈顶值并插入到第四个位置
- OP_insert4
复制栈顶值并插入到第五个位置
- OP_perm3
交换第二和第三个值的位置
- OP_rot3l
向左旋转栈顶前三个值
- OP_rot4l
向左旋转栈顶前四个值
- OP_rot5l
向左旋转栈顶前五个值
- OP_rot3r
向右旋转栈顶前三个值
- OP_perm4
将栈顶第二个值插入到第四个位置
- OP_perm5
将栈顶第二个值插入到第五个位置
- OP_swap
将栈顶前两个值互换
- OP_swap2
将栈顶前四个值互换
- OP_fclosure
获取常量池中的bytecode function，并创建对应的closure对象
- OP_call0
有0个参数的函数调用
- OP_call1
有1个参数的函数调用
- OP_call2
有2个参数的函数调用
- OP_call3
有3个参数的函数调用
- OP_call
读取参数个数，调用函数
- OP_tail_call
尾调用优化，调用函数
- OP_call_constructor
调用构造函数
- OP_call_method
调用方法函数
- OP_tail_call_method
尾调用优化，调用方法函数
- OP_array_from
创建array，参数为element值
- OP_apply
函数apply调用
- OP_return
函数返回
- OP_return_undef
函数返回undefined
- OP_check_ctor_return
检查构造函数的返回值
- OP_check_ctor
检查构造函数使用new
- OP_check_brand
- OP_add_brand
- OP_throw
抛出错误
- OP_throw_error
抛出内置运行时错误
- OP_eval
- OP_apply_eval
- OP_regexp
根据预编译创建正则表达式
- OP_get_super
获取object对应的prototype对象
- OP_import
- OP_check_var
检查全局变量是否存在
- OP_get_var_undef
获取全局变量，不抛出错误
- OP_get_var
获取全局变量，抛出错误
- OP_put_var
写全局变量，正常写
- OP_put_var_init
写全局变量，lexically写
- OP_put_var_strict
严格模式下写全局变量
- OP_check_define_var
检查全局变量是否定义
- OP_define_var
定义全局变量
- OP_define_func
定义全局函数
- OP_get_loc
获取函数内指定位置的局部变量
- OP_put_loc
写入函数内指定位置的局部变量
- OP_set_loc
写入函数内指定位置的局部变量，并Dup
- OP_get_arg
获取指定位置的函数参数
- OP_put_arg
写入指定位置的函数参数
- OP_set_arg
写入指定位置的函数参数，并Dup
- OP_get_var_ref
获取指定位置的闭包变量
- OP_put_var_ref
写入指定位置的闭包变量
- OP_set_var_ref
写入指定位置的闭包变量，并Dup
- OP_get_var_ref_check
获取指定位置的闭包变量，并检查是否初始化
- OP_put_var_ref_check
写入指定位置的闭包变量，并检查是否初始化
- OP_put_var_ref_check_init
写入指定位置的闭包变量，并初始化
- OP_set_loc_uninitialized
写入指定位置的闭包变量uninitialized值
- OP_get_loc_check
获取函数指定位置的局部变量，并检查是否初始化
- OP_put_loc_check
写入函数指定位置的局部变量，并检查是否初始化
- OP_put_loc_check_init
写入函数指定位置的局部变量，并初始化
- OP_close_loc
将函数内变量移入闭包变量
- OP_make_loc_ref
- OP_make_arg_ref
- OP_make_var_ref_ref
- OP_make_var_ref
- OP_goto
跳转到指定偏移位置
- OP_goto16
跳转到指定偏移位置，偏移量为16位
- OP_goto8
跳转到指定偏移位置，偏移量为8位
- OP_if_true
判断值是否为真值，若为真值，跳转到指定偏移位置
- OP_if_false
判断值是否为假值，若为假值，跳转到指定偏移位置
- OP_if_true8
偏移量为8位
- OP_if_false8
偏移量为8位
- OP_catch
- OP_gosub
跳转到指定位置，加上偏移量
- OP_ret
- OP_for_in_start
- OP_for_in_next
- OP_for_of_start
- OP_for_of_next
- OP_for_await_of_start
- OP_iterator_get_value_done
- OP_iterator_check_object
- OP_iterator_close
- OP_iterator_close_return
- OP_iterator_next
- OP_iterator_call
- OP_lnot
逻辑否运算符
- OP_get_field
获取对象中指定的属性，并释放对象
- OP_get_field2
获取对象中指定的属性，并压入栈顶
- OP_put_field
设置对象中指定的属性
- OP_private_symbol
- OP_get_private_field
获取对象中的私有属性
- OP_put_private_field
设置对象中的私有属性
- OP_define_private_field
定义对象的私有属性
- OP_define_field
定义对象的属性
- OP_set_name
设置对象的name属性
- OP_set_name_computed
设置对象的name属性，使用计算值
- OP_set_proto
设置对象的prototype
- OP_set_home_object
- OP_define_method
定义对象的方法属性
- OP_define_method_computed
定义对象的方法属性，函数名为计算值
- OP_define_class
定义class
- OP_define_class_computed
定义class，类名为计算值
- OP_get_array_el
获取以索引访问的属性值，并释放对象
- OP_get_array_el2
获取以索引访问的属性值，并push到栈顶上
- OP_get_ref_value
- OP_get_super_value
- OP_put_array_el
写入以索引访问的属性值
- OP_put_ref_value
- OP_put_super_value
- OP_define_array_el
定义以索引访问的属性值
- OP_append
向数组中添加可迭代的值
- OP_copy_data_properties
- OP_add
对两个数进行相加
- OP_add_loc
对两个数相加，其中一个使用索引到函数内局部变量
- OP_sub
对两个数进行相减
- OP_mul
对两个数进行相乘
- OP_div
对两个数进行相除
- OP_mod
对两个数做模运算
- OP_pow
对两个数做幂运算
-
