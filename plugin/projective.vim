"TODO check nomodifiable issue: $vim -> \s -> \/ -> <CR> -> i <-
"TODO tree update
"TODO tree functions names
"TODO add window mappings
"TODO add make clean (bang to :Make)
"TODO manage special buffers properly (set/open/close/toggle)

let project_make_console = 1
let project_console_sp_mod = 'bo 15'
let project_fbrowser_sp_mod = 'vert to 45'
let project_tree_sp_mod = 'vert to 45'
let project_switcher_sp_mode = 'bo 8'
let project_dir = '~/projective'

augroup project_commands
    au!
    au VimLeave * if exists('g:project_type')
                \ | exe 'call' g:project_type . '#Project_cleanup()'
                \ | endif
augroup END

""""""""""""""""""""""""""""""""""""""""""""""""
" search by Agrep
"TODO check avialability
""""""""""""""""""""""""""""""""""""""""""""""""
command! -nargs=1 Search :call Agrep([<q-args>, s:files, g:project_name . ' search> ' . <q-args>])

""""""""""""""""""""""""""""""""""""""""""""""""
" make
""""""""""""""""""""""""""""""""""""""""""""""""
command! Make :call Make()

func! Make()
    cclo
    call g:Project_make_pre()

    let cmd = g:project_make_cmd
    if g:project_make_dir != ''
	let dir = expand(g:project_make_dir)
	if !isdirectory(dir)
	    call mkdir(dir)
	endif
	let cmd = 'cd ' . dir . '; ' . g:project_make_cmd
    endif

    call Project_run_job(cmd, function('s:make_cb'), g:project_make_console ? 'make' : '')
endfunc

func! s:make_cb(channel)
    let r = g:Project_make_post()
    if type(r) == type(0)
	return
    endif

    call setqflist(r)
    if len(getqflist())
	call s:close_window('Console')
	copen
	redr
	" TODO better message?
	echohl WarningMsg | echo len(getqflist()) . ' errors were found!' | echohl None
    else
	cclose
	redr
	echohl MoreMsg | echo ' No errors found!' | echohl None
    endif
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" fuzzy file finder
""""""""""""""""""""""""""""""""""""""""""""""""
map <silent> <leader>/ :call <SID>fuzzy_file_finder()<CR>

set ballooneval

func! Project_fbrowser_get(lnum)
    return s:files[s:files_ids[a:lnum-1]]
endfunc

func! s:open_file(cmd)
    let line = line('.')
    if winnr('$') > 1
        wincmd p
    else
        new
    endif
    call s:close_window('Files-browser')
    exe a:cmd Project_fbrowser_get(line)
endfunc

func! s:fuzzy_file_finder()
    if !exists('s:files') | return | endif
    call s:set_window('Files-browser', '', 0, g:project_fbrowser_sp_mod)
    map <silent> <buffer> <CR>          :call <SID>open_file('e')<CR>
    map <silent> <buffer> <2-LeftMouse> :call <SID>open_file('e')<CR>
    map <silent> <buffer> t             :call <SID>open_file('tabe')<CR>
    map <silent> <buffer> s             :call <SID>open_file('sp')<CR>
    setlocal bexpr=Project_fbrowser_get(v:beval_lnum)
    "TODO rank and sort the matches
    "TODO add history
    let files_stack = [range(0, len(s:files)-1)]
    let filter_str = ''
    setlocal modifiable
    let s:files_ids = files_stack[-1]
    call s:display_files(1)
    echo 'Search file> '
    let ch = getchar() " TODO
    while nr2char(ch) != "\<CR>" && nr2char(ch) != "\<Esc>"
	if 0 " TODO illegal input
	    let ch = getchar()
	    continue
	endif
	if ch != "\<BS>"
	    let filter_str .= nr2char(ch)
	    let pattern = substitute(filter_str,'.', '&[^/]\\{-}', 'g')
	    let pattern = substitute(pattern,'\.','\\.','g')
	    let pattern .= '[^/]*$'
	    let _ids = []
	    for i in s:files_ids
		if s:files[i] =~ pattern
		    call add(_ids, i)
		endif
	    endfor
	    call add(files_stack, _ids)
	    let s:files_ids = _ids
	elseif filter_str != ''
	    let filter_str = filter_str[:-2]
	    call remove(files_stack, -1)
	    let s:files_ids = files_stack[-1]
	endif
	call s:display_files(1)    
	echo 'Search> ' . filter_str
	let ch = getchar()
    endwhile
    call s:display_files(0)
    setlocal nomodifiable
endfunc

func! s:display_files(avail_space)
    let len = len(s:files_ids)
    if a:avail_space
	let len = min([len, winheight(0)])
    endif
    let lines = []
    let i = 0
    while i < len
	call add(lines, matchstr(s:files[s:files_ids[i]], '[^/]*$'))
	let i += 1
    endwhile
    call setline(1, lines)
    exe 'silent!' i+1 . ',$d _'
    call cursor(1,1)
    redr
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" Project API
""""""""""""""""""""""""""""""""""""""""""""""""
"TODO call init() function when loading a project (source <lang>.vim only once)

func! Project_set_files(files)
    let s:files = a:files
    call Project_save_file(s:files, 'files.p')
endfunc

func! Project_get_files()
    return s:files
endfunc

" TODO is this function needed?
func! Project_add_files(files)
    let fd = {}
    for f in s:files
	let fd[f] = 1
    endfor
    for f in a:files
	if !has_key(fd, f)
	    call add(s:files, f)
	    let fd[f] = 1
	endif
    endfor
    call Project_save_file(s:files, 'files.p')
endfunc

func! Project_expand(fname)
    return expand(g:project_dir . '/' . g:project_name . '/' . a:fname)
endfunc

func! Project_save_file(flines, fname)
    let fname = Project_expand(a:fname)
    if fname =~ '/'
	let dir = substitute(fname, '/[^/]*$', '', '')
	if !isdirectory(dir)
	    call mkdir(dir, 'p')
	endif
    endif
    call writefile(a:flines, fname)
endfunc

func! Project_read_file(fname)
    let fn = Project_expand(a:fname)
    if glob(fn) != ''
        return readfile(fn)
    else
        return []
    endif
endfunc

func! Project_run_job(cmd, close_cb, title)
    "TODO add 'active' indicator to the console
    "TODO check for running job
    let job_options = { 'close_cb': a:close_cb }
    if a:title != ''
	let s:console_bnr = s:set_window('Console', a:title, 1, g:project_console_sp_mod)
	call extend(job_options, {
			\ 'out_io': 'buffer',
			\ 'out_buf': s:console_bnr,
			\ 'out_modifiable': 0,
			\ 'err_io': 'buffer',
			\ 'err_buf': s:console_bnr,
			\ 'err_modifiable': 0 })
    endif

    let g:project_job = job_start(['/bin/sh', '-c', a:cmd], job_options)
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" Project select
""""""""""""""""""""""""""""""""""""""""""""""""
map <silent> <leader>s :call <SID>project_select()<CR>

let g:project_name = ''

func! s:project_select()
    call s:set_window('Switch-project', '', 0, g:project_switcher_sp_mode)
    setlocal nowrap
    setlocal cursorline

    map <silent> <buffer> <CR> :call <SID>project_init(substitute(getline('.'), '\s\+', '', '')) \| bw!<CR>
    
    let projects = map(glob(g:project_dir . '/*/init.vim', 0, 1), {k, v -> matchstr(v, '[^/]*\ze/init\.vim')})
    setlocal modifiable
    call setline(1, projects)
    setlocal nomodifiable
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" general utilities
""""""""""""""""""""""""""""""""""""""""""""""""
let s:empty_func = {-> 0}

func! System(cmd)
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

func! s:project_init(name)
    if exists('g:project_type')
	exe 'call' g:project_type . '#Project_cleanup()'
    endif
    let g:Project_make_post          = s:empty_func
    let g:Project_make_pre           = s:empty_func
    let g:Project_tree_init_node     = s:empty_func
    let g:Project_tree_user_mappings = s:empty_func " TODO use API and remove when doing cleanup

    let g:project_name = a:name
    let s:files = Project_read_file('files.p')
    exe 'source' Project_expand('init.vim')
    exe 'call' g:project_type . '#Project_init()'
endfunc

func! s:set_window(bufname, title, return, sp_mod)
    "TODO add a function arg for special mappings and settings
    let base_win = winnr()
    if bufnr(a:bufname) < 0
	exe 'silent' a:sp_mod 'new' a:bufname
	setlocal buftype=nofile bufhidden=hide noswapfile
	setlocal norelativenumber " TODO
    else
	call s:open_window(a:bufname, a:sp_mod)
    endif
    exe 'setlocal statusline=['.a:bufname.(a:title != '' ? '::'.a:title : '').'\ '.g:project_name.']%=%p%%'
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

""""""""""""""""""""""""""""""""""""""""""""""""
" tree
""""""""""""""""""""""""""""""""""""""""""""""""
map <leader>t :call <SID>tree_browser()<CR>

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

func! s:tree_browser()
    let s:tree_bnr = s:set_window('Tree', '', 0, g:project_tree_sp_mod)
    setlocal nowrap
    setlocal conceallevel=3 concealcursor=nvic

    map <silent> <buffer> <CR>          : call <SID>toggle_node_under_cursor()<CR>
    map <silent> <buffer> <2-LeftMouse> : call <SID>toggle_node_under_cursor()<CR>

    "TODO leaf icon?
    syn match tree_icon    "[▿▸⎘]"
    syn match tree_conceal "[|!:]"    conceal contained
    syn match tree_hl1     "![^!]\+!" contains=tree_conceal
    syn match tree_hl2     ":[^:]\+:" contains=tree_conceal
    syn match tree_hl3     "|[^|]\+|" contains=tree_conceal
    hi def link tree_hl1   Question
    hi def link tree_hl2   CursorLineNr
    hi def link tree_hl3   Directory
    hi def link tree_icon  Statement

    "TODO add user mappings API
    call g:Project_tree_user_mappings()

    setlocal modifiable
    call s:display_tree(0, g:nodes[0])
    setlocal nomodifiable
endfunc

func! New_tree()
    unlet! g:nodes
    let g:nodes = []
endfunc

func! New_node(name)
    let node = deepcopy(g:node)
    call add(g:nodes, node)
    let node.id = len(g:nodes) - 1
    let node.name = a:name
    return node
endfunc

func! New_child(node, child)
    call add(a:node.children, a:child.id)
    let a:child.parent = a:node.id
endfunc

func! Get_node_by_line(line)
    let s:n_count = 0
    return s:node_count_(g:nodes[0], a:line)
endfunc

func! Get_parent(node)
    if a:node.parent == -1 | return {} | endif
    return g:nodes[a:node.parent]
endfunc

func! Get_children(node)
    return map(copy(a:node.children), {k, v -> g:nodes[v]})
endfunc

func! Get_path(node)
    let scope = [a:node.name]
    let id = a:node.parent
    while id != -1
	let scope = [g:nodes[id].name] + scope
	let id = g:nodes[id].parent
    endwhile
    return scope
endfunc

func! Get_node_by_path(path, ...)
    if empty(g:nodes) | return {} | endif
    let children = a:0 ? a:1.children : [0]
    for p in a:path
        let found = 0
	for c in children
	    if g:nodes[c].name == p
		let children = g:nodes[c].children
                let found = 1
		break
	    endif
	endfor
        if !found | return {} | endif
    endfor
    return g:nodes[c]
endfunc

let s:tree_bnr = 0

func! Hl_tree()
    let winnr = bufwinnr(s:tree_bnr)
    if winnr > 0
        let saved_winnr = winnr()
        if saved_winnr !=  winnr | exe winnr 'wincmd w' | endif
        let s:n_count = 0
        setlocal modifiable
        call s:hl_tree_(g:nodes[0])
        setlocal nomodifiable
        if saved_winnr !=  winnr | exe saved_winnr 'wincmd w' | endif
    endif
endfunc

func! s:hl_tree_(node)
    let s:n_count += 1
    if a:node.hlr
	call setline(s:n_count, s:node_str(a:node, matchstr(getline(s:n_count), '^ *\ze\S')))
        let a:node.hlr = 0
    endif
    if a:node.expanded
	for c in a:node.children
	    call s:hl_tree_(g:nodes[c])
	endfor
    endif
endfunc

func! Set_node_hl(node, hl)
    if a:node.hl != a:hl
        let a:node.hl = a:hl
        let a:node.hlr = 1
    endif
endfunc

func! Save_tree()
    for n in g:nodes
        let n.hl = 0
        let n.hlr = 0
    endfor
    call Project_save_file([string(g:nodes)], 'tree.p')
endfunc

func! Load_tree()
    let m = Project_read_file('tree.p')
    if empty(m)
        let g:nodes = []
    else
        let g:nodes = eval(m[0])
    endif
endfunc

func! s:node_str(node, indent)
    if a:node.hl
        let hlc = a:node.hl == 3 ? '|' : a:node.hl == 2 ? ':' : '!'
    else
        let hlc = ''
    endif
    let sign = a:node.leaf ? '⎘' : a:node.expanded ? '▿' : '▸'
    return printf('%s%s %s%s%s', a:indent, sign , hlc, a:node.name, hlc)
endfunc

func! s:display_tree(line, node)
    let s:lines = []
    call s:display_tree_(a:node, repeat('  ', len(Get_path(a:node))-1))
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
    let node = Get_node_by_line(line)
    setlocal modifiable
    call s:remove_node_view(line, node)
    let node.expanded = !node.expanded
    if !node.cached
        call g:Project_tree_init_node(node)
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

func! s:node_count_(node, max)
    let s:n_count += 1
    if s:n_count == a:max
	return a:node
    elseif a:node.expanded
	for s in a:node.children
	    let node = s:node_count_(g:nodes[s], a:max)
	    if !empty(node)
		return node
	    endif
	endfor
    endif
    return {}
endfunc
