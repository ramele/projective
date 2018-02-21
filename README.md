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
```
cd ~/.vim
git clone https://github.com/ramele/projective
git clone https://github.com/ramele/agrep
```
And adding the following lines to your .vimrc:
```
set rtp+=~/.vim/projective
set rtp+=~/.vim/agrep
```

**Set up a new project**
Open the projects menu with `<leader>s `.
Note: `<leader>` is backslash by default (`\`). See `:h leader` for more details.
Type `<C-n>` to create a new project and choose your project's language from the list. You'll be asked to enter a name for the project -use any name and hit `<Enter>`. Now, a new tab will be opened with a template configuration file called `init.vim` for the project. Edit the following settings:
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
Edit the other options in this file if you need, otherwise keep their default value.
You can use any command or script for `projective_make_cmd` that eventually calls ncvlog and ncelab, for example: irun. Note that you can use your proprietary compilation and elaboration script. `-parseinfo include` is the only ncvlog flag that should be included if you want the internal syntax checker to recognize your -incdir compiler directives (if you choose to use your own wrapper script, make sure that it includes this switch in the irun or ncvlog command line).
The settings will take place after you'll save the file. When you already have a project (one or more) you can switch between projects from this menu. Use `<C-e>` if you want to change the settings of an existing project.
You can also select a project using the following command:
`:Projective <project-name>`
This is useful to automatically load a default project from your .vimrc or to define mappings,
After you've created a new project or selected an existing one, you're ready to go:

### Usage

**Make**  
In order to use the above features, you'll need to build your project first. One successful build is required to extract the relevant information from the log file.
To build a project use the`:Make` command. It will run `projective_make_cmd` in `projective_make_dir` and parse the log file to build the internal database and detect errors. Use the `!` modifier (`:Make!`) to clean the existing build first. This will run the `projective_make_clean_cmd` instead of the regular command.
Hit `<C-c>` in the console window to kill the make process.
If there are compilation or elaboration errors, the quickfix window will be opened and you'll be able to jump to each error location. See `:h quickfix` for details.

**Syntax checker**  
Each time you save a verilog file the syntax checker will be called in the background. This is actually a simple ncvlog call with the current file. In addition to this file, two additional files will be compiled as well:
* defines.v file - contains all the `define directives across the entire project
* ncvlog.args -  contains all the `incdir directives` (only if you've included the `-parseinfo include` ncvlog switch).
The Quickfix window will be opened automatically if errors have been detected.

**File browser**  
Use `<leader>/` command to open the fuzzy matching search window to open a file from the project's files list. Type few letters from the file name, the files list will be filtered accordingly. The letters do not need to appear in consecutive order or to match at the beginning of the file name.
You can navigate in the filtered list with `<C-j>` and `<C-k>` (or `<Up>` and `<Down>`). Hit `<Enter>` to open the highlighted file, `<C-s>` to open it in a split window or `<C-t>` for a new tab. Press `<Esc>` to cancel the search.
Note: You can use the fuzzy match in other Projective windows as well (e.g., projects menu window).

**Search**  
Use `:Search '<pattern>'`. This command will call the great [Agrep](https://github.com/ramele/agrep) plugin to search in the project's file list. See `:h agrep` for details.

**Design browser**  
In order to use the design browser smart window and other features, the project's tree should be generated from the design snapshot first. Use the `:UpdateDesign` command to generate this database, it will open a new SimVision window. This may take some time, depending on your design size. Use this command when the design structure changes to update the hierarchy tree.
Type `<leader>t` to open the design browser window. In this window you can hit `<Enter>` or `double click left mouse button` to expand or collapse hierarchies. Use the `e` command to open the file of the module under the cursor.
The current scope will be highlighted in the design browser window. When the cursor is in the range of a module instance it will be highlighted in the design browser window as well and you'll see the direction of the signal under-the-cursor near to the instance name. Use `<leader>vv` to change the scope and open the file of the instance under the cursor and `<leader>vf` to go to the parent scope.
Note: All verilog specific commands start with `<leader>v` so you only need to memorize the last letter. In this case think of`\vv` as a down arrow (`v`). `\vf` direction is up because the `f` key is above `v` on the keyboard.
When you're searching for a signal name and the cursor is on a match that is connected to a signal with a different name, the search pattern will be adjusted automatically as you travel between hierarchies. This behavior can be disabled with `let projective_verilog_smart_search = 0` in your .vimrc.

Hit `<F5>` in the design browser window to refresh the design tree (useful if it has been changed outside of the current vim instance).

When the design browser is available, the scope is updated automatically as you switch buffers. If the scope can't be determined (usually, when there is more than one instance of the current module), or it you want to change the current scope to a different instance of the current module use the `<leader>vi` command to search and switch instances.

**Connect to SimVision**  
The `:Simvision` command will open a new SimVision window. You can provide a path to waves database as an argument to this command, otherwise only the design snapshot will be loaded. The signal under the cursor can be sent to SimVision using `<leader>vs` (send to schematic) and `<leader>vw` (send to waveform). This also works in visual mode for multiple signals. You can visually select a block of code and type the above commands -all the signals that appear in the highlighted area will be sent to SimVision.
After you are done with the SimVision debugging, you can go back to Vim and type `<leader>vg`. This will open the scope that is currently highlighted in Simvision.
When a simulation log-file is opened in Vim, you can type `<leader>vc` to toggle the cursor binding mode. While this mode is on, SimVision cursor will follow the simulation time of the line under the cursor.
