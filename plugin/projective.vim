let projective_make_console     = 1
let projective_console_sp_mod   = 'bo 15'
let projective_fbrowser_sp_mod  = 'vert to 45'
let projective_tree_sp_mod      = 'vert to 45'
let projective_switcher_sp_mode = 'bo 8'
let projective_dir              = '~/projective'

augroup projective_commands
    au!
    au VimLeave * if exists('g:projective_project_type')
                \ | exe 'call' g:projective_project_type . '#Projective_cleanup()'
                \ | endif
augroup END

""""""""""""""""""""""""""""""""""""""""""""""""
" search by Agrep
""""""""""""""""""""""""""""""""""""""""""""""""
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
command! -bang Make     : call Projective_make(<bang>0)
command!       Makekill : call job_stop(projective_job)

func! Projective_make(clean)
    cclo
    call g:Projective_before_make(a:clean)

    let cmd = a:clean ? g:projective_make_clean_cmd : g:projective_make_cmd
    if g:projective_make_dir != ''
	let dir = expand(g:projective_make_dir)
	if !isdirectory(dir)
	    call mkdir(dir)
	endif
	let cmd = 'cd ' . dir . '; ' . cmd
    endif

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
	copen
	redr
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

func! Projective_fbrowser_get(lnum)
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
    exe a:cmd Projective_fbrowser_get(line)
endfunc

func! s:fuzzy_cb(ch, msg)
    if a:msg == '--'
        let s:fuzzy_done = 1
    else
        call add(s:files_ids, a:msg)
    endif
endfunc

func! s:fuzzy_file_finder()
    if !exists('s:files') | return | endif
    if !exists('s:fuzzy_perl')
        let s:fuzzy_perl = globpath(&rtp, 'perl/fuzzyfind.pl')
    endif
    call s:set_window('Files-browser', '', 0, g:projective_fbrowser_sp_mod)
    map <silent> <buffer> <CR>          :call <SID>open_file('e')<CR>
    map <silent> <buffer> <2-LeftMouse> :call <SID>open_file('e')<CR>
    map <silent> <buffer> t             :call <SID>open_file('tabe')<CR>
    map <silent> <buffer> s             :call <SID>open_file('sp')<CR>
    setlocal bexpr=Projective_fbrowser_get(v:beval_lnum)
    "TODO add history
    let s:files_ids = range(0, len(s:files)-1)
    let filter_str = ''
    let files = Projective_path('files.p')
    setlocal modifiable
    call s:display_files(1)
    echo 'find file> '
    let job = job_start(s:fuzzy_perl . ' ' . files, {'out_cb': function('s:fuzzy_cb')})
    let channel = job_getchannel(job)
    let ch = getchar() " TODO
    while nr2char(ch) != "\<CR>" && nr2char(ch) != "\<Esc>"
	if 0 " TODO illegal input
	    let ch = getchar()
	    continue
	endif
        let s:fuzzy_done = 0
        let s:files_ids = []
	if ch != "\<BS>"
            let filter_str .= nr2char(ch)
	    call ch_sendraw(channel, nr2char(ch) . "\n")
	else
            if filter_str != ''
                let filter_str = filter_str[:-2]
            endif
	    call ch_sendraw(channel, "<\n")
	endif
        while !s:fuzzy_done
            sleep 10m
        endwhile
	call s:display_files(1)    
	echo 'find file> ' . filter_str
	let ch = getchar()
    endwhile
    call s:display_files(0)
    setlocal nomodifiable
    call job_stop(job)
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
    return expand(g:projective_dir . '/' . g:projective_project_name . '/' . a:fname)
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
endfunc

func! s:job_cb(func, channel)
    let g:projective_job_status = 'Done'
    redraws!
    call a:func(a:channel)
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" Project select
""""""""""""""""""""""""""""""""""""""""""""""""
map <silent> <leader>s :call <SID>project_select()<CR>

let g:projective_project_name = ''

func! s:project_select()
    call s:set_window('Switch-project', '', 0, g:projective_switcher_sp_mode)
    setlocal nowrap
    setlocal cursorline

    map <silent> <buffer> <CR> :call <SID>project_init(getline('.')) \| bw!<CR>
    map <silent> <buffer> e    :call <SID>edit_project()<CR>
    
    let projects = map(glob(g:projective_dir . '/*/init.vim', 0, 1), {k, v -> matchstr(v, '[^/]*\ze/init\.vim')})
    setlocal modifiable
    call setline(1, projects)
    setlocal nomodifiable
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

func! s:project_init(name)
    if exists('g:projective_project_type')
	exe 'call' g:projective_project_type . '#Projective_cleanup()'
    endif
    let g:Projective_after_make         = s:empty_func
    let g:Projective_before_make        = s:empty_func
    let g:Projective_tree_init_node     = s:empty_func
    let g:Projective_tree_user_mappings = s:empty_func " TODO use API and remove when doing cleanup

    let g:projective_project_name = a:name
    let s:files = Projective_read_file('files.p')
    exe 'source' Projective_path('init.vim')
    let g:projective_make_dir = expand(g:projective_make_dir)

    exe 'call' g:projective_project_type . '#Projective_init()'
endfunc

func! s:edit_project()
    let saved_p = g:projective_project_name
    let g:projective_project_name = getline('.')
    bw!
    exe 'tabe' Projective_path('init.vim')
    let g:projective_project_name = saved_p
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

""""""""""""""""""""""""""""""""""""""""""""""""
" tree
"TODO move to autoload
""""""""""""""""""""""""""""""""""""""""""""""""
map <leader>t :call Projective_open_tree_browser()<CR>

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
    let s:tree_bnr = s:set_window('Tree', '', 0, g:projective_tree_sp_mod)
    setlocal nowrap
    setlocal conceallevel=3 concealcursor=nvic

    map <silent> <buffer> <CR>          : call <SID>toggle_node_under_cursor()<CR>
    map <silent> <buffer> <2-LeftMouse> : call <SID>toggle_node_under_cursor()<CR>

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
    call g:Projective_tree_user_mappings()

    setlocal modifiable
    call s:display_tree(0, g:nodes[0])
    setlocal nomodifiable
endfunc

func! Projective_new_tree()
    unlet! g:nodes
    let g:nodes = []
endfunc

func! Projective_new_node(name)
    let node = deepcopy(g:node)
    call add(g:nodes, node)
    let node.id = len(g:nodes) - 1
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
    if a:node.parent == -1 | return {} | endif
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

func! Projective_hl_tree()
    let winnr = s:tree_bnr ? bufwinnr(s:tree_bnr) : 0
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

func! Projective_set_node_hl(node, hl)
    if a:node.hl != a:hl
        let a:node.hl = a:hl
        let a:node.hlr = 1
    endif
endfunc

func! Projective_save_tree()
    for n in g:nodes
        let n.hl = 0
        let n.hlr = 0
    endfor
    call Projective_save_file([string(g:nodes)], 'tree.p')
endfunc

func! Projective_load_tree()
    let m = Projective_read_file('tree.p')
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