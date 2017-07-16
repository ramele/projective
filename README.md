# Projective
### Real IDE in Vim

_**This plugin is under development**_

#### Supported languages (so far):

#### Verilog (using Cadence environment):
Main features:
* Asynchronous make and quickfix
* Automatic syntax checker
* Fast files navigation (file name fuzzy matching)
* Design browser
* Advanced Search
* Integration with SimVision (schematic Tracer)
* Fast switching between projects

#### _e_ Language

### Requirements
Vim 8.0, Linux

### Installation
You can use your favorite plugin manager or install directly by:
```
cd ~/.vim
git clone https://github.com/ramele/projective
git clone https://github.com/ramele/agrep
```
In your .vimrc:
```
set rtp+=~/.vim/projective
set rtp+=~/.vim/agrep
```

**Creating new projects:**  
First, create a root directory for Projective:
```
cd ~
mkdir projective
```

Under this directory you can create sub directories for each project.
To create a new Verilog project named 'my_design':
```
cd ~/projective
mkdir my_design
cd my_design
```
In each project directory there should be a file called init.vim.
For verilog projects use:

~/projective/my_design/init.vim:
```
" projective init file
""""""""""""""""""""""
let projective_project_type       = 'verilog'
let projective_make_dir           = '~/my_design_snapshot'
let projective_make_cmd           = 'irun -elaborate -sv -top my_design_tb ~/my_design_files.f -parseinfo include'
let projective_make_clean_cmd     = projective_make_cmd . ' -clean'
let projective_verilog_log_file   = 'irun.log'
let projective_verilog_design_top = 'my_design_tb'
"let projective_verilog_64_bit    = 1
"let projective_verilog_grid      = 'nc run'
```
For the `projective_make_cmd` option you can use any command or script that
eventually calls ncvlog and ncelab, for example: irun. Note that you can use
your regular compilation and elaboration script. `-parseinfo include` is the
only ncvlog flag that should be included if you want the internal syntax
checker to recognize your -incdir compiler directives.

For e language projects use the `projective_e_log_file` option.

### Usage

**Make**  
In order to use the above features, you'll need to build your project (one
successful build is required to extract the relevant information from the log
file). Use `<leader>s` command to open the project selection window. While in
this window you can hit `<Enter>` to choose a project or `e` to edit the
project's init.vim file.
Alternatively, you can select any project directly by running:

:Projective <project-name>

If <project-name> is not provided then the current project will be reloaded. 

_Note:_ `<leader>` is backslash by default. See `:h leader` for more details.

To build a project use `:Make` or `:Make!`. The ! modifier is used to call the
make clean command (`projective_make_clean_cmd` instead of `projective_make_cmd`).
Hit `<C-C>` in the console window to kill the make process.

If there are compilation or elaboration errors, the quickfix window will be
opened with the relevant errors. See `:h quickfix` for details.

**Syntax checker**  
Each time you save a verilog file the syntax checker will be called in the
background. This is actually a simple ncvlog call with the current file you're
editing. In addition to the current file two other files will be added to the
ncvlog command;
* defines.v file - contains all the `define directives across the entire project
* ncvlog.args -  contains all \`incdir directives. The `-parseinfo include`
  ncvlog flag is required for that.
The Quickfix window will be open automatically if errors have been detected.

**File browser**  
Use `<leader>/` command to open the file search window. Type few letters from
the file name, the files list will be filtered accordingly. The letters do not
have to be in a consecutive order, or match at the beginning of the file name.
You can navigate in the filtered list with `<C-J>` and `<C-k>` (or `<Up>` and
`<Down>`). Hit `<Enter>` to open the file under cursor, `<C-s>` to open it in a
split window or `<C-t>` to open in a new tab.

**Search**  
Use `:Search '<pattern>'`. This command will call Agrep with the project's file
list. See `:h agrep` for details.

**Design browser**  
In order to use the design browser window, the project tree should be generated
from the design snapshot. Use the `:UpdateDesign` command command to generate
the database, it will open a new SimVision window if there is no one associated
with the current Vim instance already. In may take some time, depends on your
project size. Use this command when the design structure changes to regenerate
the hierarchy DB.  The `<leader>t` command will open the design browser window.
While in this window you can use `<Enter>` or `<left mouse double click>` to
expand or hide hierarchies. Use the `e` command to open the file of the current
scope. The current scope will be highlighted in the design browser window. When
the cursor in on an module instance you can use `<leader>vv` to change the
scope and open the files of the instance under the cursor. `<leader>va` will
bring you to the scope in which the current module is instanced in.
Use <F5> in the design browser window to refresh the design tree (useful if it
has been changed outside of the current vim instance)

**Schematic**  
Use the `:Simvision` command to open a new SimVision window connected to the
current Vim instance if there is no one yet. When Vim is connected to SimVision
you can use `<leader>vs` to send the signal under the cursor to the Schematic
tracer or `<leader>vf` to go to Sync Vim with the Schematic tracer scope and
the highlighted signal.
