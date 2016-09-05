" Project file for Verilog
" TODO take work path from log name
" TODO decide where to handle empty nodes
"
func! s:set_make()
    if s:mini_make
	let s:saved_make_opts = [g:project_make_dir, g:project_make_cmd, g:project_make_console]
	let g:project_make_dir = Project_expand('ncvlog')
	let g:project_make_cmd = 'ncvlog -sv -f ncvlog.args defines.v ' . expand('%:p')
	let g:project_make_console = 0
	call timer_start(1000, function('s:restore_make_opts'))
    else
        " TODO temp. autocmd for quickfix is not triggered
        let s:global_qf_open = 0
"	let s:clean_build = (glob(g:project_make_dir . '/' . 'INCA_libs') != '')
    endif
endfunc

func! s:restore_make_opts(timer)
    let [g:project_make_dir, g:project_make_cmd, g:project_make_console] = s:saved_make_opts
endfunc

func! s:mini_make()
    if s:global_qf_open | return | endif
    let s:mini_make = 1
    call Make()
endfunc

func! s:make_post()
    if s:mini_make
	let lines = Project_read_file('ncvlog/ncvlog.log')
    else
	let lines = readfile(expand(g:project_make_dir . '/' . g:verilog_log_file))
	call s:build_internal(lines) "TODO read the log only once
    endif
    let my_qf = []
    for l in lines
	if l =~ '\C^nc\w*: \*E,'
	    let m = matchlist(l, '(\([^)]*\),\(\d\+\)|\?\(\d*\)):\s*\(.*\)')
	    if !empty(m)
		if m[3] == ''
		    let m[3] = 0
		endif
		let fname = (m[1] =~ '^[/~$]' ? m[1] : expand(g:project_make_dir . '/' . m[1]))
		call add(my_qf, {'filename': fname, 'lnum': m[2], 'col': m[3]+1, 'text': m[4], 'type': 'E'})
	    else
		call add(my_qf, {'text': l, 'type': 'E'})
	    endif
	endif
    endfor
    if !s:mini_make && !empty(my_qf)
        let s:global_qf_open = 1
    endif
    let s:mini_make = 0
    return my_qf
endfunc

func! s:build_internal(lines) " TODO export to perl
    let incdirs = []

    let fd = {}
    let i = 0
    for f in s:files
	let fd[f] = i
        let i += 1
    endfor

    for l in a:lines
	if l =~ '^file:'
	    let f = matchstr(l, '^file:\s*\zs.*')
	    if f !~ '^[~/$]'
		let f = g:project_make_dir . '/' . f
	    endif
            if has_key(fd, f)
                let idx = fd[f]
            else
                call add(s:files, f)
                let fd[f] = i
                let idx = i
                let i += 1
            endif
        elseif l =~ '^\s*module .*:v$'
            let s:modules[matchstr(l, '\w*\ze:v')] = idx " TODO is it safe to use :v?
	elseif l =~ '\c^\s*-INCDIR'
	    call add(incdirs, l)
	endif
    endfor
    call Project_set_files(s:files)
    call Project_save_file([string(s:modules)], 'modules.p')
    call Project_save_file(incdirs, 'ncvlog/ncvlog.args')
"    echo 'Updating `defines...'
    let cmd = "grep -h '^\\s*`define' " . join(s:files)
    call Project_save_file([cmd], '.tmp_exec.sh')
    let cmdf = Project_expand('.tmp_exec.sh')
    let perm = getfperm(cmdf)
    if perm[2] != 'x'
	call setfperm(cmdf, 'rwx' . perm[3:])
    endif
    let s:defines = []
    call job_start(['/bin/sh', '-c', cmdf], {
		\ 'out_cb': function('s:add_define'),
		\ 'close_cb': function( 's:close_defines')})
endfunc

func! s:add_define(channel, msg)
    call add(s:defines, a:msg)
endfunc

func! s:close_defines(channel)
    call Project_save_file(s:defines, 'ncvlog/defines.v')
    unlet s:defines
"    echo 'defines updated!'
endfunc

func! s:new_tree()
    call New_tree()
    let node = New_node(g:verilog_design_top)
    let node.module = g:verilog_design_top
endfunc

func! verilog#Project_init()
    let g:Project_make_post = function('s:make_post')
    let g:Project_make_pre = function('s:set_make')
    let g:Project_tree_init_node = function('s:scope_init')
    let g:Project_tree_user_mappings = function('s:tree_mappings')

    let s:files = Project_get_files()
    let m = Project_read_file('modules.p')
    if empty(m)
        let s:modules = {}
    else
        let s:modules = eval(m[0])
    endif

    call Load_tree()
    if empty(Get_node_by_path([g:verilog_design_top]))
        call s:new_tree()
    endif

    let s:tree_file = expand(g:project_make_dir . '/scope_tree.txt')
    if !exists('s:cdn_dir')
        " TODO how to manage lang directories?
        let s:cdn_dir = globpath(&rtp, 'languages/verilog-IES')
        let s:get_scope_pl = s:cdn_dir . '/get_scope.pl'
    endif

    augroup verilog_mini_make
	au!
	au BufWritePost *.v call s:mini_make()
	au BufWritePost *.v call s:get_instances_map()
        au BufEnter *.v if !s:event_ignore
                    \ | call s:update_cur_scope()
                    \ | call s:update_hl('')
                    \ | endif
        au CursorMoved *.v call s:hl_path()
        " TODO vim_dev
"        au BufLeave quickfix let s:global_qf_open = 0
    augroup END

    map <silent> <leader>va :call <SID>scope_up()<CR>
    map <silent> <leader>vv :call <SID>scope_down()<CR>
    map <silent> <leader>vs :call <SID>send_to_schematic()<CR>
    map <silent> <leader>vf :call <SID>get_schematic()<CR>

    let s:mini_make = 0
    let s:prev_ln = 0
    let s:prev_inst = ''
    let s:prev_hl = {}
    let s:global_qf_open = 0

"    echo g:project_type . ' init done!'
endfunc

func! verilog#Project_cleanup()
    au! verilog_mini_make
    call Save_tree()
    unlet s:modules
    unlet s:files

    unmap <leader>va
    unmap <leader>vv
    unmap <leader>vs
    unmap <leader>vf
"    echo g:project_type . ' cleanup done!'
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" hierarchy
""""""""""""""""""""""""""""""""""""""""""""""""
func! Generate_tree()
    " TODO add cdslib and workdir options
    let cmd = 'cd ' . g:project_make_dir . ';'
                \ . ' simvision -nosplash -lytdir ' . s:cdn_dir . '/layout -layout tiny'
                \ . ' -snapshot worklib.' . g:verilog_design_top . ':v'
                \ . ' -memberplugindir ' . s:cdn_dir . '/scope_tree_plugin'
                \ . ' -input ' . s:cdn_dir . '/tree.tcl'
    let g:simvision_tree_cmd = cmd " TODO remove
    call job_start(['/bin/sh', '-c', cmd], { 'close_cb': function('s:update_tree') })
endfunc

func! s:update_tree(channel)
    call s:new_tree()
    echo 'Design hierarchy was updated!'
endfunc

func! s:scope_init(node)
    let cmd = s:get_scope_pl . ' ' . s:tree_file . ' ' . join(Get_path(a:node), '.')
    let ret = System(cmd)
    for s in ret
        let sp = split(s)
        let child = New_node(sp[1])
        let child.leaf = (sp[0] == '-')
        let child.module = sp[2]
        call New_child(a:node, child)
    endfor
    let a:node.cached = 1
endfunc

func! s:tree_mappings()
    map <silent> <buffer> e :call <SID>edit_tree_scope()<CR>
endfunc

let s:event_ignore = 0

func! s:edit_tree_scope()
    let node = Get_node_by_line(line('.'))
    " TODO open a new window if needed
    let s:event_ignore = 1
    silent! wincmd p
    call <SID>edit_scope(node, 'e')
endfunc

func! s:edit_scope(node, cmd)
    let s:event_ignore = 1
    let f = s:files[s:modules[a:node.module]]
    exe a:cmd f
    keepj norm! gg
    call search('^\s*module\s\+' . a:node.module)
    norm! zt
    let b:verilog_scope = Get_path(a:node)
    let s:cur_scope = a:node
    if !a:node.cached
        " TODO use async job
        call s:scope_init(a:node)
    endif
    call s:get_instances_map()
    call s:update_hl('')
    let s:event_ignore = 0
endfunc

func! s:update_cur_scope()
    let s:cur_scope = {}
    if exists('b:verilog_scope')
        let s:cur_scope = Get_node_by_path(b:verilog_scope)
    endif
    call s:get_instances_map()
endfunc

func! s:get_instances_map()
    "TODO might not work properly with old grep (2.5.1) - two matches in a
    "line with -o issue
    let s:instances = {}
    if empty(s:cur_scope) | return | endif
    let inst = map(Get_children(s:cur_scope), {k, v -> v.name})
    let cmd = 'grep -onE ''\<(' . join(inst, '|') . ')\>\s*($|\(|/[/*])|\);'' ' . expand('%')
                \ . ' | grep -A 1 '':[^)]'''
    call job_start(['sh', '-c', cmd], {'close_cb': function('s:get_instances_map_cb')})
endfunc

func! s:get_instances_map_cb(channel)
    " TODO confirm grep results by searching for the actual module name
    let inst_lnum = 0
    while ch_status(a:channel) == 'buffered'
	let line = ch_read(a:channel)
        if line[0] == '-' | continue | endif
	let l = matchstr(line, '^\d\+')
        let t = matchstr(line, ':\zs\()\|\w\+\)')
	if t[0] != ')'
            let inst_lnum = l
	    let inst_name = t
	elseif inst_lnum
	    for i in range(inst_lnum, l)
		let s:instances[i] = inst_name
	    endfor
	    let inst_lnum = 0
	endif
    endwhile
endfunc

" TODO add protection
func! s:scope_up()
    let node = Get_parent(s:cur_scope)
    call s:edit_scope(node, 'e')
endfunc

func! s:scope_down()
    let node = Get_node_by_path([s:instances[line('.')]], s:cur_scope)
    call s:edit_scope(node, 'e')
endfunc

" TODO use node ids for speed?
func! s:hl_path()
    if line('.') == s:prev_ln | return | endif
    let s:prev_ln = line('.')
    let cur_inst = get(s:instances, line('.'), '')
    if cur_inst == s:prev_inst | return | endif
    let s:prev_inst = cur_inst
    call s:update_hl(cur_inst)
endfunc

func! s:update_hl(cur_inst)
    if a:cur_inst == ''
        let hl_scope = s:cur_scope
        let hl_val = 2
    else
        let hl_scope = Get_node_by_path([a:cur_inst], s:cur_scope)
        let hl_val = 3
    endif
    while !empty(s:prev_hl)
        call Set_node_hl(s:prev_hl, 0)
	let s:prev_hl = Get_parent(s:prev_hl)
    endwhile
    let s:prev_hl = hl_scope
    while !empty(hl_scope)
	call Set_node_hl(hl_scope, hl_val)
	if hl_val > 1 | let hl_val -= 1 | endif
        let hl_scope = Get_parent(hl_scope)
    endwhile
    call Hl_tree()
endfunc

""""""""""""""""""""""""""""""""""""""""""""""""
" Simvision
""""""""""""""""""""""""""""""""""""""""""""""""

func! s:simvision_eval(cmd)
    return ch_evalraw(g:ch, "request {" . a:cmd . "}\n")
endfunc

func! s:get_word_under_cursor()
    return matchstr(getline('.'), '\w*\%' . col('.') . 'c\w*')
endfunc

func! s:send_to_schematic()
    let design_obj = join(Get_path(s:cur_scope), '.') . '.' . s:get_word_under_cursor()
    call s:simvision_eval('schematic add ' . design_obj . '; select set ' . design_obj)
endfunc

func! s:get_schematic()
    let cs = s:simvision_eval('schematic curselection')
    let cs = substitute(cs, '^.*::', '', '')
    let sp = split(cs, '\.')
    let scope = Get_node_by_path([sp[0]])
    for s in sp[1:-2] " TODO add protection
        if !scope.cached
            " TODO use async job
            call s:scope_init(scope)
        endif
        let scope = Get_node_by_path([s], scope)
    endfor
    call s:edit_scope(scope, 'e')
    call search('\<' . matchstr(sp[-1], '\w\+') . '\>')
    norm! zz
endfunc

"let ch = ch_open('localhost:5678', {'mode':'nl'})
"simvision -schematic -input ~/server.tcl -cdslib cds.lib -snapshot worklib.top
