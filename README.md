# prefixell (+ λ)° : functional language that compiles to lua

![Logo](https://github.com/TBApknoob12MC/prefixell/raw/main/img/logo.png)

---

## Overview

Prefixell is a functional programming language that compiles to Lua. It features a Lisp-like syntax with prefix notation, gradual typing, pattern matching, and monadic operations. The language is a joke.

## Features

- **Functional Programming**: First-class functions, immutability(fake), and higher-order functions
- **Gradual Typing (I, guess?)**: Compile-time type "choking"
- **Pattern Matching**: Powerful pattern matching with guards
- **Monadic Operations**: Support for monadic bind (`>>=`) and do-notation
- **Lisp + haskell like Syntax**: Prefix notation similar to Lisp (bruh), mainly inspired by haskell (bruh x2)
- **Lua Interoperability**: Compiles directly to Lua code

## Installation

1. Clone the repository:
```bash
git clone https://github.com/TBApknoob12MC/prefixell
```

2. Make sure you have Lua installed on your system

## Usage

### Compilation Mode
```bash
lua(5.2+) prefixell.lua c input.lc output.lua
```
Compiles `input.lc` to `output.lua`.

### REPL Mode
```bash
lua(5.2+) prefixell.lua r
```
Starts the interactive REPL. You can also load an entry file:
```bash
lua(5.2+) prefixell.lua r entry.lc
```

In the REPL, you can:
- Enter expressions to evaluate them
- Type `:q` to quit
- Type `:d` to toggle debug mode (shows generated Lua code)

## Quickstart

Let's write a Hello, World! program:

```
print "Hello, World!"
```

That's it? The haskellers will start to scream like I just did a war crime.

So here is the haskellers approved version of it:

```
fn main do [ finish (putStr "Hello, World!") ] ;;
fcall main
```

Trust me, it's superior /j.

Let's make an 'add 1' program:

```
fn main do [
inputnum <- (fcall getLine) ;
add_one <- (pure (+ (tonumber inputnum) 1)) ;
finish (putStr add_one)
] ;;
fcall main
]
```

now try compiling deez programs.

## Language Syntax

### Basic Types
- Numbers: `42`, `3.14`
- Booleans: `true`, `false`
- Strings: `"hello world"`
- Nil: `nil`

### Functions
Define anonymous functions using lambda syntax:
```
\x : (+ x 1)
```

Define named functions:
```
fn inc \x : (+ x 1)
```

### Function Application
Functions are applied by juxtaposition(the what lmao.Search it in google):
```
inc 5 ;;
(\x y : (+ x y)) 3 4
```

### Arithmetic and Logic
Basic operators: `+`, `-`, `*`, `/`, `^`, `%`
Comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`
Logical: `and`, `or`

String concatenation: `++`

### Conditionals
```
if condition then_expr else_expr
```

### Pattern Matching
```
match value [
  pattern1 => result1 ;
  pattern2 => result2 ;
  _ => default_result
]
```

### Lists
Create lists with square brackets:
```
[1 2 3 4]
```

### Tables
Create tables with curly braces:
```
{value1 value2}
```

### Let Bindings
Bind values to variables:
```
let x 42 : (+ x 1)
```

### Type Annotations
Annotate types:
```
type add N N : N
```

### Monadic Operations
Use monadic bind with `>>=`:
```
(>>= some_computation (\result : process result))
```

Or use do-notation:
```
do [
  x <- computation1 ;
  y <- computation2 ;
  finish (+ x y)
]
```

### Modules
Define modules:
```
module MyModule
```

Export values:
```
export MyModule functionName value
```

Import modules:
```
use "path/to/module"
```

### Including other source code files

To include another prefixell source file in current program:
```
include path/to/file.lc ;;
```

This reads `file.lc` and replaces that `include` block with its content.

### Macros

Macros are kind of like compile-time functions.

It gets replaced with its body at compile-time.

```
def a_macro arg1 arg2 as (+ arg1 arg2) ;;
a_macro 1 2 -- becomes (+ 1 2) at compile time
```

The only problem with macros are that if there is error, it won't give line and column numbers.

## Built-in Functions

The compiler provides many built-in functions:

### List Operations
- `cons h t` - Creates a list node
- `car li` - Gets the head of a list
- `cdr li` - Gets the tail of a list
- `totbl li` - Converts a linked list to a Lua table
- `tols li` - Converts a Lua table to a linked list
- `at li idx` - Gets element at index
- `l_map fun li` - Maps a function over a list
- `l_filter pred li` - Filters a list
- `l_foldl fun acc li` - Folds a list left
- `l_rev li` - Reverses a list
- `l_range first last step` - Creates a range list
- `l_zip li1 li2` - Zips two lists
- `l_unzip li` - Unzips a zipped list

### Table Operations
- `tdump tbl` - Dumps a table as string
- `tblidx tbl idx` - Indexes into a table

### IO Operations
- `putStr str` - Prints a string
- `getLine` - Reads a line from stdin
- `writeFile path content` - Writes content to file
- `appendFile path content` - Appends content to file
- `readFile path` - Reads content from file

### Functional Utilities
- `pure x` - Creates a constant function
- `fcall fun` - Calls a function
- `>>=` - Monadic bind operator

## Build System

If you ever wanted to automate compiling multiple files, IN A JOKE LANGUAGE,there is a make but worse thing.

First, create a `cfg.lc.lua` file in your project:

```lua
return {
  entry = "main.lc", -- the name of your main file
  dep_list = { -- dependencies
    ["dep1.lc"] = {
      "dep1dep1.lc",
      "dep1dep2.lc"
    },
    "dep2.lc"
  },
  outputs = { -- specify output name mapping. otherwise, file.lc -> file.lua 
    ["dep2.lc"] = "newname.lua"
  },
  targets = { -- targets
    run = {
    prerun = {"clean","build"}, -- runs other targets before running this target
    "lua5.2 main.lua"
    },
    build = {"lua5.2 prefixell.lua build"},
    clean = {"rm dep1dep1.lua dep1dep2.lua dep1.lua dep2.lua main.lua"}
  }
}
```

now if you run `prefixell.lua build`, it will compile deeper deps first, and finally the entry file.

If a target like `prefixell.lua build run` is given, it will execute the target's command instead of compiling the project.

If there is `prerun` for a target, it will run those targets first and then runs current.

## Examples

### Hello World
```
(putStr "Hello, World!" ) |> fcall
```

### Simple Function
```
type double N : N ;;
fn double \x : (* x 2)
```

### List Processing
```
let numbers ([1 2 3 4 5]) : ((l_map (\x : (* x 2)) numbers) |> totbl)
```

### Fibonacci Sequence
```
fn fib \n : (if (<= n 1) n (+ (fib (- n 1)) (fib (- n 2))))
```

### Pattern Matching Example
```
fn describe \x : (match x [
  0 => "zero" ;
  n | (< n 0) => "negative" ;
  _ => "positive"
  ])
```

Fibonacci with pattern matching:

```
fn fib \n a b : (match n [
  0 => a ;
  _ => (fib (- n 1) b (+ a b))
])
```
## License

MPL-2.0

---