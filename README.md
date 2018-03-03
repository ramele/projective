# Projective
### Real IDE in Vim

_**This plugin is under development**_

#### Supported languages (so far):

#### Verilog (using Incisive/Xcelium simulators):
Main features:
* Asynchronous make and quickfix
* Automatic syntax checker
* Fast navigation using fuzzy matching
* Enhanced design browser
* Advanced Search
* Highly integrated with SimVision
#### _e_ Language

### Requirements
Vim 8.0, Linux

### Installation
You can use your favorite plugin manager or install it manually by:
```sh
$ cd ~/.vim
$ git clone https://github.com/ramele/projective
$ git clone https://github.com/ramele/agrep
```
And adding the following lines to your .vimrc:
```viml
set rtp+=~/.vim/projective
set rtp+=~/.vim/agrep
```

**Set up a new project**  
Open the projects menu by typing `<leader>s`.  
Note: `<leader>` is backslash by default so we will use `\` here. See `:h leader` for more details.  
First time users will be asked to create a new project; Choose language and name for the project and press `<Enter>`. A new tab will be opened with a template configuration file called `init.vim` for the project. Edit the following settings:
```viml
let projective_project_type = 'verilog'

" Where to run :Make (will be created automatically if not exists):
let projective_make_dir = '$TOP/work'

" Specify the command to run with :Make (you can use irun/xrun or a proprietary script):
let projective_make_cmd = 'irun -sv -f irun.args -elaborate -parseinfo include'

" Define how to run a clean build (when you call :Make! -with '!'):
let projective_make_clean_cmd = projective_make_cmd . ' -clean'
```
For verilog projects, edit also:
```viml
" Name of the log-file that is created by :Make :
let projective_verilog_log_file = 'irun.log'

" Top design module name:
let projective_verilog_design_top = 'top'
```
Edit the other options in this file if necessary, or keep their default values. The settings will take place after you save the file.  
`projective_make_cmd` can be an irun command or your proprietary compilation and elaboration script that eventually calls irun or ncvlog and ncelab.  
The irun/ncvlog `-parseinfo include` command line option is required for the internal syntax checker to locate the files that are included using the `include compiler directive (if you are using your own wrapper script, make sure it passes this flag to irun or ncvlog).  
Next time you open Vim or when you want to switch to anoter project, open this menu and select a project from the list.  
The followin commands are available in the projects menu window:  
* `<C-e>` - Edit the settings of a project  
* `<C-n>` - Create a new project  
* `<C-d>` - Delete a project  
* `<C-r>` - Remane a project's name  
You can also select a project using the following command:  
`:Projective <project-name>`  
This is useful to automatically load a default project from your .vimrc (see below) or when defining mappings.  
Now, after you've created your first project, you're ready to go:  

### Usage

**Make**  
In order to use the above features, you'll need to build your project first. One successful build is required to extract the relevant information from the log file.  
To build a project use the `:Make` command. This will run `projective_make_cmd` in `projective_make_dir` and scan the log file in order to detect errors and build the internal database. Use the `!` modifier (`:Make!`) to clean the existing build first. This will run `projective_make_clean_cmd` instead.  
Hit `<C-c>` in the console window to kill the make process.  
If there are compilation or elaboration errors, the quickfix window will be opened and you'll be able to jump to the errors. See `:h quickfix` for details.

**Syntax checker**  
The syntax checker is running in the background every time a verilog file is being saved. This is actually a simple ncvlog call that compiles the current file along with two additional files:  
* defines.v file - contains all the `define directives across the entire project.  
* ncvlog.args -  contains all the `incdir directives` (only if you've included the `-parseinfo include` ncvlog switch).  

These two files are created automatically when you run :Make. The Quickfix window will be opened if errors have been detected.

**File browser**  
 Type `\/` to open a file from the project's file list. The search is done using a fuzzy-matching pattern: just type few letters from the file name and the file list will be filtered accordingly. The letters do not need to appear exactly as they are in the file name.  
You can navigate in the filtered list with `<C-j>` and `<C-k>` (or `<Up>` and `<Down>`). Hit `<Enter>` to open the highlighted file, `<C-s>` to open it in a split window or `<C-t>` for a new tab. Press `<Esc>` to cancel the search.  
Note: You can use the fuzzy-search in other Projective's windows as well (e.g., projects menu window).

**Search**  
Use `:Search '<pattern>'` to find a word or a regular-expression in the project. This command will call the great [Agrep](https://github.com/ramele/agrep) plugin to search in the project's file list. See `:h agrep` for details.  

**Design browser**  
In order to use the design browser window and other project navigation features, the design hierarchy tree should be generated from the design snapshot first. Use the `:UpdateDesign` command to generate this database, it will open a Simvision window and automatically close it when done. This may take some time, depending on your design size. Use this command when the design structure changes to update the hierarchy tree.  
Type `\t` to open the design browser window. In this window you can hit `<Enter>` or `double click left mouse button` to expand or collapse hierarchies. Use the `e` command to open the file of the module under the cursor. The current scope will be highlighted in the design browser window.  
As you move the cursor in a verilog file and the cursor is in a range of a module instance, this instance will be highlighted in the design browser window and you'll see an arrow next to it that indicates the direction of the signal under the cursor.  

Use `\vv` to change the scope and open the file of the instance under the cursor and `\vf` to go to the parent scope.  
Note: All verilog specific commands start with `\v` so you only need to memorize the last letter. In this case you can think of`\vv` as a down arrow (`v`). `\vf` direction is up because the `f` key is above `v` on the keyboard.  
When you're searching for a signal name and the cursor is on a match that is connected to a signal with a different name in other hierarchy, the search pattern will be adjusted automatically as you travel between hierarchies. This behavior can be disabled with `let projective_verilog_smart_search = 0` in your .vimrc.  

Hit `<F5>` in the design browser window to refresh the design tree (useful if it has been changed outside of the current vim instance).  

The scope is updated automatically as you switch between buffers. If the scope can't be determined (usually when there is more than one instance of the current module), or if you want to change the scope to a different instance of the current module use the `\vi` command. It will open a sub-tree of the design containing only instances of the current module. Use `e` to select and edit an instance or press `<Esc>` to cancel the search.  

**Connect to SimVision**  
The `:Simvision` command can be used to open a Simvision window. You can provide a path to waves database as an argument to this command, otherwise only the design snapshot will be loaded. You can send the signal under the cursor to Simvision by typing `\vs` (send to schematic) or `\vw` (send to waveform). This also works in visual mode for multiple signals -you can visually select a block of code and type the above commands. All the signals that appear in the highlighted area will be sent to Simvision.  
When you are done with the Simvision debugging, you can go back to Vim and type `\vg` to open the scope that is currently selected in Simvision.  

When a simulation log-file is opened in Vim, you can type `\vc` to toggle the cursor binding mode. While this mode is active, Simvision cursor will follow the simulation time of the line under the cursor.  

**Useful tips**  
* Add this to your .vimrc if you want to automatically load a project on Vim's startup:
```viml
au! VimEnter * Projective my-project
```
* You can start a debug session with the log file opened in Vim and connected to Simvision from the command-line by running:
```sh
$ gvim "+Projective my-design-project" "+Simvision waves.shm" "+e specman.elog" "+norm \t"
```
This is very useful setup; The "TimeA" cursor in the waveform window will follow Vim's cursor position in the log file (when enabled with `\vc`). You'll be able to open any scope in Vim and then send it to Simvision. This is way faster than searching hierarchies in Simvision!  

**Known issues**  
Currently, there is a problem to share a scope with Simvision when one of its ancestors is instanced under a generate block.
