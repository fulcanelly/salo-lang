# salo-lang

salo lang is a my first simple language writen in ruby and created only for educational purposes

I write It like a training for my future project.
The are a lot of things here are taken from ruby and scala.
Actually almost all values in **salo lang** is ruby primitives.

### About implementation
Grammar of this lang described in LALR.
It executes code using tree-walk interpreter via AST.
Also, it have no bindings in scope so it behaves like python from this edge.

### Dependencies
- [ruby](https://github.com/ruby/ruby)
- [rly](https://github.com/farcaller/rly)

### How to run 
Simply go to folder with this project and run
```
ruby src/main.rb <path to salo program file>
```
### Examples & Tests
Due of absence of documentation examples would be good way to learn a litle bit about this language.
You can find them in `tests` folder.

It's actually far away from complete and have many problems as you can see from list below

### Todo list
- [ ] Fix operator precedence
- [ ] Make modules more flexible 
- [ ] Lambdas, arrays, booleans 
- [ ] Default values in functions
- [x] Virtual Machine
- [ ] Documentanion 

It would great if you help with some of these probles.
