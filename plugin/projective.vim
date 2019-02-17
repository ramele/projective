" Projective plugin for Vim
" Author: Ramel Eshed

if !exists('projective_dir')
    let projective_dir = '~/projective'
endif
if !exists('projective_make_console')
    let projective_make_console = 1
endif
if !exists('projective_fuzzy_match_no_path')
    let projective_fuzzy_match_no_path = 0
endif
" default :new modifiers
if !exists('projective_console_sp_mod')
    let projective_console_sp_mod = 'bo 15'
endif
if !exists('projective_fuzzy_sp_mod')
    let projective_fuzzy_sp_mod = 'bo 10'
endif
if !exists('projective_tree_sp_mod')
    let projective_tree_sp_mod = 'vert to 45'
endif

let projective_dir = expand(projective_dir)

augroup projective_commands
    au!
    au VimLeave * call s:project_cleanup()
    au ColorScheme * call s:save_cursor_hl()
augroup END

func! s:save_cursor_hl()
    " this is faster than setting 'gcr'
    " TODO vim's bug - when the screes is small the output is 2 lines
    let g:hl_cursor_cmd = 'hi ' . substitute(execute('hi Cursor')[1:], '\s*xxx\|\n', '', 'g')
endfunc

func! s:hide_cursor()
    hi! link Cursor Conceal
endfunc

func! s:show_cursor()
    exe g:hl_cursor_cmd
endfunc

call s:save_cursor_hl()

""""""""""""""""""""""""""""""""""""""""""""""""
" search by Agrep
""""""""""""""""""""""""""""""""""""""""""""""""
" TODO search should take additional grep flags
command! -nargs=1 Search :call s:search(<q-args>)

func! s:search(regexp)
    if !exists('*Agrep')
        echoerr 'Projective search requires Agrep plugin to be installed. Get the latest version from https://github.com/ramele/agrep'
        return
    endif
    call Agrep({'regexp': a:regexp, 'files': s:files, 'title': g:projective_project_name . ' search> ' . a:regexp})
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" make
""""""""""""""""""""""""""""""""""""""""""""""""
command! -bang Make :call Projective_make(<bang>0)

func! Projective_make(clean)
    cclose
    call g:Projective_before_make(a:clean)

    let cmd = a:clean ? g:projective_make_clean_cmd : g:projective_make_cmd
    if !isdirectory(g:projective_make_dir)
        call mkdir(g:projective_make_dir)
        if !isdirectory(g:projective_make_dir)
            echoerr "couldn't create " . g:projective_make_dir . " directory"
            return
        endif
    endif
    let cmd = 'cd ' . g:projective_make_dir . '; ' . cmd

    call Projective_run_job(cmd, function('s:make_cb'), g:projective_make_console ? 'make' : '')
endfunc

func! s:make_cb(channel)
    let r = g:Projective_after_make()
    if type(r) == type(0)
	return
    endif

    call setqflist(r)
    if !empty(getqflist())
	call s:close_window('Console')
	bo copen
	redr
	echohl WarningMsg | echo len(getqflist()) . ' errors were found!' | echohl None
    else
	cclose
	redr
	echohl MoreMsg | echo ' No errors found!' | echohl None
    endif
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" fuzzy finder
""""""""""""""""""""""""""""""""""""""""""""""""
func! s:fuzzy_cb(ch, msg)
    if a:msg == '--'
        let s:fuzzy_done = 1
    else
        call add(s:fuzzy_matches, a:msg)
    endif
endfunc

let s:special_ch = { "\<Esc>": 1, "\<C-j>": 1, "\<C-k>": 1, "\<BS>": 1, "\<Down>": 1, "\<Up>": 1}

func! s:get_char(ops)
    while 1
        let ch = getchar()
        if type(ch) != v:t_string
            let ch = nr2char(ch)
        endif
        if getcharmod() == 0 && ch =~ '^[a-zA-Z0-9_.-]$' || has_key(s:special_ch, ch) || has_key(a:ops, ch)
            return ch
        endif
    endwhile
endfunc

func! s:fuzzy_find(name, list, file, ops)
    if !exists('s:fuzzy_perl')
        let s:fuzzy_perl = globpath(&rtp, 'perl/fuzzyfind.pl')
    endif
    let winid = win_getid()
    call s:set_window(a:name, '', 0, g:projective_fuzzy_sp_mod)
    setlocal cursorline
    let s:fuzzy_matches = range(0, len(a:list)-1)
    let filter_str = ''
    if a:file != ''
        let listf = a:file
    else
        let listf = Projective_path('/fuzzy.p')
        call writefile(a:list, listf)
    endif
    setlocal modifiable
    call s:display_matches(a:list)
    echo 'find> '
    let fuzzy_exe = s:fuzzy_perl . ' ' . listf . (g:projective_fuzzy_match_no_path ? ' --no-path' : '')
    let job = job_start(fuzzy_exe, {'out_cb': function('s:fuzzy_cb')})
    let channel = job_getchannel(job)
    let ch = s:get_char(a:ops)
    while ch != "\<Esc>" && !has_key(a:ops, ch)
        call s:hide_cursor()
        if ch == "\<C-j>" || ch == "\<Down>"
            if line('.') < len(s:fuzzy_matches)
                if line('.') == line('$')
                    call setline(line('$') + 1, a:list[s:fuzzy_matches[line('$')]])
                endif
                norm! j
            endif
        elseif ch == "\<C-k>" || ch == "\<Up>"
            if line('.') > 1
                norm! k
            endif
	else
            let s:fuzzy_done = 0
            let s:fuzzy_matches = []
            if ch != "\<BS>"
                let filter_str .= ch
                call ch_sendraw(channel, ch . "\n")
            else
                if filter_str != ''
                    let filter_str = filter_str[:-2]
                endif
                call ch_sendraw(channel, "<\n")
            endif
            while !s:fuzzy_done
                sleep 10m
            endwhile
            call s:display_matches(a:list)    
            call clearmatches()
            let i = 0
            let hl = '\V\c\.\*' . substitute(filter_str, '.', '&\\.\\{-}', 'g')
            while i < len(filter_str)
                call matchadd('Title', substitute(hl, '\%'. (9+i*7) . 'c.', '\\zs&\\ze', '')) 
                let i += 1
            endwhile
        endif
        redr
        call s:show_cursor()
        echo 'find> ' . filter_str
        let ch = s:get_char(a:ops)
    endwhile
    call job_stop(job)
    if a:file == ''
        call delete(listf)
    endif
    setlocal nomodifiable
    call clearmatches()
    let id = line('.') - 1
    bw
    call win_gotoid(winid)
    redr!
    if ch == "\<Esc>" || empty(s:fuzzy_matches)
        return
    else
        let Func = a:ops[ch]
        call Func(a:list[s:fuzzy_matches[id]])
    endif
endfunc

func! s:display_matches(list)
    let len = min([len(s:fuzzy_matches), winheight(0)])
    let lines = []
    let i = 0
    while i < len
	call add(lines, a:list[s:fuzzy_matches[i]])
	let i += 1
    endwhile
    call setline(1, lines)
    exe 'silent!' i+1 . ',$d _'
    call cursor(1,1)
    redr
endfunc

" fuzzy file finder
map <silent> <leader>/ :call <SID>fuzzy_file_finder()<CR>

func! s:fuzzy_file_finder()
    if !exists('s:files')
        return
    endif
    let ops = { "\<CR>": function('s:fuzzy_edit', ['e']),
                \ "\<C-s>": function('s:fuzzy_edit', ['sp']),
                \ "\<C-t>": function('s:fuzzy_edit', ['tabe'])}
    call s:fuzzy_find('Project-files', s:files, Projective_path('files.p'), ops)
endfunc

func! s:fuzzy_edit(cmd, file)
    exe a:cmd a:file
    norm `"
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" Projective API
""""""""""""""""""""""""""""""""""""""""""""""""
"TODO call init() function when loading a project (source <lang>.vim only once)

func! Projective_set_files(files)
    let s:files = a:files
    call Projective_save_file(s:files, 'files.p')
endfunc

func! Projective_get_files()
    return s:files
endfunc

func! Projective_path(fname)
    return g:projective_dir . '/' . g:projective_project_name . '/' . a:fname
endfunc

func! Projective_save_file(flines, fname)
    let fname = Projective_path(a:fname)
    if fname =~ '/'
	let dir = substitute(fname, '/[^/]*$', '', '')
	if !isdirectory(dir)
	    call mkdir(dir, 'p')
	endif
    endif
    call writefile(a:flines, fname)
endfunc

func! Projective_read_file(fname)
    let fn = Projective_path(a:fname)
    if glob(fn) != ''
        return readfile(fn)
    else
        return []
    endif
endfunc

func! Projective_run_job(cmd, close_cb, title)
    "TODO check for running job
    let job_options = { 'close_cb': function('s:job_cb', [a:close_cb]) }
    if a:title != ''
        let g:projective_job_status = 'Running'
	let s:console_bnr = s:set_window('Console', a:title, 1, g:projective_console_sp_mod, 1)
	call extend(job_options, {
			\ 'out_io': 'buffer',
			\ 'out_buf': s:console_bnr,
			\ 'out_modifiable': 0,
			\ 'err_io': 'buffer',
			\ 'err_buf': s:console_bnr,
			\ 'err_modifiable': 0 })
    endif

    let g:projective_job = job_start(['/bin/sh', '-c', a:cmd], job_options)
    let g:projective_ch = job_getchannel(g:projective_job)
endfunc

func! s:job_cb(func, channel)
    let g:projective_job_status = 'Done'
    redraws!
    call a:func(a:channel)
endfunc

func! Projective_ch_send(msg)
    call ch_sendraw(g:projective_ch, a:msg . "\n")
endfunc

func! s:check_dir()
    if !isdirectory(g:projective_dir)
        call mkdir(g:projective_dir)
    endif
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" Projective menu
""""""""""""""""""""""""""""""""""""""""""""""""
map <silent> <leader>s :call <SID>menu()<CR>
command! -nargs=? -bang Projective :if <bang>0 | call s:project_cleanup() | else | call s:project_init(<q-args>) | endif

func! s:menu()
    call s:check_dir()
    let gl = glob(g:projective_dir . '/*/init.vim', 1, 1)
    let projects = map(gl, {k, v -> matchstr(v, '[^/]*\ze/init\.vim')})
    if empty(projects)
        let input = s:input('There are no projects yet. Do you want to set up a project (y/n)? ')
        if input == 'y' || input == 'yes'
            call s:project_new()
        endif
    else
        let ops = { "\<CR>": function('s:project_init'),
                    \ "\<C-e>": function('s:project_edit'),
                    \ "\<C-d>": function('s:project_delete'),
                    \ "\<C-r>": function('s:project_rename'),
                    \ "\<C-n>": function('s:project_new')}
        call s:fuzzy_find('Projective-menu', projects, '', ops)
    endif
endfunc

func! s:project_edit(name)
    exe 'tabe' g:projective_dir . '/' . a:name . '/init.vim'
    augroup project_init_command
        au!
        exe 'au BufWritePost <buffer> call s:project_init("' . a:name . '")'
    augroup END
endfunc

func! s:project_delete(name)
    let input = s:input('Are you sure you want to delete ' . a:name. ' (yes/no)? ')
    if input != 'yes' || g:projective_dir == '' || a:name == ''
        return
    endif
    if a:name == g:projective_project_name
        call s:project_cleanup()
    endif
    call delete(g:projective_dir . '/' . a:name, 'rf')
    call s:menu()
endfunc

func! s:project_rename(name)
    let new_name = s:input('Enter a new name for ' . a:name . ': ')
    if new_name == ''
        return
    endif
    let init = 0
    if a:name == g:projective_project_name
        call s:project_cleanup()
        let init = 1
    endif
    call Projective_system('mv ' . g:projective_dir . '/' . a:name . ' ' . g:projective_dir . '/' . new_name)
    if init
        call s:project_init(new_name)
    endif
    call s:menu()
endfunc

func! s:project_new(...)
    if !exists('s:plugin_dir')
        " TODO always use this as projective's root
        let s:plugin_dir = filter(split(&rtp, ','), {i, v -> v =~ '\/projective$'})[0]
    endif
    let lang_path = glob(s:plugin_dir . '/languages/*', 1, 1)
    let lang = map(lang_path, {k, v -> substitute(v, '.*/', '', '')})
    let ops = {"\<CR>": function('s:create_proj')}
    call s:fuzzy_find('Select-language', lang, '', ops)
endfunc

func! s:create_proj(lang)
    let name = s:input("Enter project name: ")
    if name == ''
        return
    endif
    let proj_dir = g:projective_dir . '/' . name
    call system('mkdir ' . proj_dir)
    call system('cp ' . s:plugin_dir . '/languages/' . a:lang . '/init.template ' . proj_dir . '/init.vim')
    call s:project_edit(name)
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" general utilities
""""""""""""""""""""""""""""""""""""""""""""""""
let s:empty_func = {-> 0}

func! Projective_system(cmd)
    "faster than system()
    let out = []
    let job = job_start(['/bin/sh', '-c', a:cmd],
                \ {'out_cb': {c, msg -> add(out, msg)}})
    let ch = job_getchannel(job)
    while ch_status(ch) != 'closed'
        sleep 10m
    endwhile
    return out
endfunc

func! s:project_cleanup()
    if g:projective_project_type != ''
        exe 'call' g:projective_project_type . '#Projective_cleanup()'
        let g:projective_project_type = ''
    endif
    let g:Projective_after_make         = s:empty_func
    let g:Projective_before_make        = s:empty_func
    let g:Projective_tree_init_node     = s:empty_func
    let g:Projective_tree_user_mappings = s:empty_func " TODO use API and remove when doing cleanup
    let g:projective_project_name = ''
    let s:files = []
endfunc

func! s:project_init(name)
    if a:name == ''
        if g:projective_project_name == ''
            return
        endif
        let saved_project = g:projective_project_name
    endif
    call s:check_dir()
    call s:project_cleanup()
    let g:projective_project_name = (a:name != '' ? a:name : saved_project)
    let s:files = Projective_read_file('files.p')
    exe 'source' Projective_path('init.vim')
    let g:projective_make_dir = expand(g:projective_make_dir)

    exe 'call' g:projective_project_type . '#Projective_init()'
endfunc

func! s:set_window(bufname, title, return, sp_mod, ...)
    "TODO use dictionary for special mappings and settings
    let base_win = winnr()
    if bufnr(a:bufname) < 0
	exe 'silent' a:sp_mod 'new' a:bufname
	setlocal buftype=nofile bufhidden=hide noswapfile
	setlocal norelativenumber " TODO
    else
	call s:open_window(a:bufname, a:sp_mod)
    endif
    if a:0
        exe 'setlocal statusline=['.a:bufname.(a:title != '' ? '::'.a:title : '').'\ '.g:projective_project_name.']\ *%{g:projective_job_status}*%=%p%%'
        " TODO set 'interrupted' status safely
        map <silent> <buffer> <C-C> :call job_stop(g:projective_job, 'kill')<CR>
    else
        exe 'setlocal statusline=['.a:bufname.(a:title != '' ? '::'.a:title : '').'\ '.g:projective_project_name.']%=%p%%'
    endif
    setlocal modifiable
    silent %d _
    setlocal nomodifiable
    let bufnr = bufnr('%')
    if a:return && winnr() != base_win
	wincmd p
    endif
    return bufnr
endfunc

func! s:open_window(bufname, sp_mod)
    let bufnr = bufnr(a:bufname)
    let winnr = bufwinnr(bufnr)
    if winnr > 0
	exe winnr 'wincmd w'
    elseif bufnr > 0
	exe a:sp_mod 'new +' . bufnr . 'b'
    endif
endfunc

func! s:close_window(bufname)
    let winnr = bufwinnr(a:bufname)
    if winnr > 0
	exe winnr . 'close'
    endif
endfunc

func! s:input(msg)
    let input = input(a:msg)
    redr!
    return input
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" tree
"TODO move to autoload
""""""""""""""""""""""""""""""""""""""""""""""""
map <silent> <leader>t :call Projective_open_tree_browser()<CR>

let node = {
            \ 'id'       : -1,
	    \ 'name'     : '',
	    \ 'parent'   : -1,
	    \ 'children' : [],
	    \ 'expanded' : 0,
	    \ 'leaf'     : 0,
	    \ 'cached'   : 0,
	    \ 'hl'       : 0,
	    \ 'hlr'      : 0
	    \ }

func! Projective_open_tree_browser()
    if !exists('g:nodes') || empty(g:nodes)
        " TODO not complete
        echohl WarningMsg | echo  'Projective: No tree to display' | echohl None
        return
    endif
    let s:tree_bnr = s:set_window('Tree', '', 0, g:projective_tree_sp_mod)
    " TODO
    "setlocal nowrap so=4
    setlocal conceallevel=3 concealcursor=nvic

    map <silent> <buffer> <CR>          : call <SID>toggle_node_under_cursor()<CR>
    map <silent> <buffer> <2-LeftMouse> : call <SID>toggle_node_under_cursor()<CR>

    " u25B6, u25FF
    syn match tree_icon    "[▶◿⎘]"
    syn match tree_conceal "[|!:]"    conceal contained
    syn match tree_hl1     "![^!]\+!" contains=tree_conceal
    syn match tree_hl2     ":[^:]\+:" contains=tree_conceal
    syn match tree_hl3     "|[^|]\+|" contains=tree_conceal
    hi def link tree_hl1   Question
    hi def link tree_hl2   CursorLineNr
    hi def link tree_hl3   Directory
    hi def link tree_icon  Statement

    "TODO add user mappings API
    call g:Projective_tree_user_mappings()

    setlocal modifiable
    call s:display_tree(0, g:nodes[0])
    call s:hl_tree()
    setlocal nomodifiable
endfunc

func! Projective_new_tree()
    unlet! g:nodes
    let g:nodes = []
endfunc

func! Projective_new_node(name)
    let node = deepcopy(g:node)
    let node.id = len(g:nodes)
    call add(g:nodes, node)
    let node.name = a:name
    return node
endfunc

func! Projective_new_child(node, child)
    call add(a:node.children, a:child.id)
    let a:child.parent = a:node.id
endfunc

func! Projective_get_node_by_line(line)
    let s:n_count = 0
    return s:node_count_(g:nodes[0], a:line)
endfunc

func! Projective_get_parent(node)
    if a:node.parent == -1
        return {}
    endif
    return g:nodes[a:node.parent]
endfunc

func! Projective_get_children(node)
    return map(copy(a:node.children), {k, v -> g:nodes[v]})
endfunc

func! Projective_get_path(node)
    let scope = [a:node.name]
    let id = a:node.parent
    while id != -1
	let scope = [g:nodes[id].name] + scope
	let id = g:nodes[id].parent
    endwhile
    return scope
endfunc

func! Get_node_by_path(path, ...)
    if empty(g:nodes)
        return {}
    endif
    " TODO add dummy root!
    if a:0
        let path = a:path
        let node = a:1
    else
        if a:path[0] != g:nodes[0].name
            return {}
        endif
        let path = a:path[1:]
        let node = g:nodes[0]
    endif
    for p in path
        if !node.cached
            call g:Projective_tree_init_node(node)
        endif
        let found = 0
	for c in node.children
	    if g:nodes[c].name == p
                let node = g:nodes[c]
                let found = 1
		break
	    endif
	endfor
        if !found
            return {}
        endif
    endfor
    return node
endfunc

func! Projective_is_empty_tree()
    return empty(g:nodes)
endfunc

let s:tree_bnr = 0

func! Projective_tree_refresh(mode)
    let winnr = s:tree_bnr ? bufwinnr(s:tree_bnr) : 0
    if winnr > 0
        let saved_ei = &eventignore
        set ei=all
        let saved_winnr = winnr()
        if saved_winnr !=  winnr
            call s:hide_cursor()
            exe winnr 'wincmd w'
        endif
        setlocal modifiable
        if a:mode
            call Projective_open_tree_browser()
        else
            call s:hl_tree()
        endif
        setlocal nomodifiable
        if saved_winnr !=  winnr
            exe saved_winnr 'wincmd w'
            call s:show_cursor()
        endif
        let &eventignore = saved_ei
    endif
endfunc

func! s:hl_tree()
    let s:n_count = 0
    let s:last_hl_line = 0
    call s:hl_tree_(g:nodes[0])
    if s:last_hl_line && line('.') != s:last_hl_line
        call cursor(s:last_hl_line, 1)
    endif
endfunc

func! s:hl_tree_(node)
    let s:n_count += 1
    if a:node.hlr
	call setline(s:n_count, s:node_str(a:node, matchstr(getline(s:n_count), '^ *\ze\S')))
        let a:node.hlr = 0
    endif
    if a:node.hl
        let s:last_hl_line = s:n_count
    endif
    if a:node.expanded
	for c in a:node.children
	    call s:hl_tree_(g:nodes[c])
	endfor
    endif
endfunc

func! Projective_set_node_hl(node, hl)
    if string(a:node.hl) != string(a:hl)
        let a:node.hl = a:hl
        let a:node.hlr = 1
    endif
endfunc

func! Projective_get_node_hl(node)
    return a:node.hl
endfunc

func! Projective_save_tree(name)
    " TODO refresh the tree before clearing the hl, don't move the cursor
    for n in g:nodes
        let n.hl = 0
        let n.hlr = 0
    endfor
    call Projective_save_file([string(g:nodes)], a:name)
endfunc

func! Projective_load_tree(name)
    let m = Projective_read_file(a:name)
    if empty(m)
        let g:nodes = []
    else
        let g:nodes = eval(m[0])
    endif
endfunc

let s:hl_dict = {1: '!', 2: ':', 3: '|'}

func! s:node_str(node, indent)
    if a:node.hl
        let hlc = s:hl_dict[a:node.hl[0]]
        let attr = a:node.hl[1:]
    else
        let hlc = ''
        let attr = ''
    endif
    let sign = a:node.leaf ? '⎘' : a:node.expanded ? '◿' : '▶'
    return printf('%s%s %s%s%s%s', a:indent, sign , hlc, a:node.name, hlc, attr)
endfunc

func! s:display_tree(line, node)
    let s:lines = []
    call s:display_tree_(a:node, repeat('  ', len(Projective_get_path(a:node))-1))
    if a:line
	call append(a:line, s:lines)
    else
	call setline(1, s:lines)
    endif
    unlet s:lines
endfunc

func! s:display_tree_(node, indent)
    call add(s:lines, s:node_str(a:node, a:indent))
    let a:node.hlr = 0
    if a:node.expanded
	for c in a:node.children
	    call s:display_tree_(g:nodes[c], a:indent . '  ')
	endfor
    endif
endfunc

func! s:toggle_node_under_cursor()
    let save_cursor = getcurpos()
    let line = line('.')
    let node = Projective_get_node_by_line(line)
    setlocal modifiable
    call s:remove_node_view(line, node)
    let node.expanded = !node.expanded
    if !node.cached
        call g:Projective_tree_init_node(node)
    endif
    call s:display_tree(line-1, node)
    setlocal nomodifiable
    call setpos('.', save_cursor)
endfunc

func! s:remove_node_view(line, node)
    silent exe a:line . ',+' . (s:tree_num_view_lines(a:node) - 1) . 'd _'
endfunc

func! s:tree_num_view_lines(node)
    let s:n_count = 0
    call s:node_count_(a:node, -1)
    return s:n_count
endfunc

let s:auto_tree_init = 0

func! s:node_count_(node, max)
    let s:n_count += 1
    if s:n_count == a:max
        return a:node
    else
        if s:auto_tree_init
            call g:Projective_tree_init_node(a:node)
            let a:node.expanded = 1
        endif
        if a:node.expanded
            for s in a:node.children
                let node = s:node_count_(g:nodes[s], a:max)
                if !empty(node)
                    return node
                endif
            endfor
        endif
    endif
    return {}
endfunc

func! Projective_init_recursively(limit)
    let s:auto_tree_init = 1
    let s:n_count = 0
    call s:node_count_(g:nodes[0], a:limit)
    let s:auto_tree_init = 0
endfunc

" init
let projective_project_type = ''
call s:project_cleanup()
