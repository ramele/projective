" Project file for e (Specman)
"
func! s:get_file_long(path, file)
    return (a:file =~ '^[/~$]' ? a:file : a:path . '/' . a:file)
endfunc

func! s:get_text(stop_pat, include)
    let s = ''
    let j = 0
    while s:lnum < s:len && s:lines[s:lnum] !~ a:stop_pat && j < 10
	let s .= ' ' . s:lines[s:lnum]
	let s:lnum += 1
	let j += 1
    endwhile
    if a:include && s:lnum < s:len
	let s .= ' ' . s:lines[s:lnum]
    else
	let s:lnum -= 1
    endif
    return substitute(s, '\s\+', ' ', 'g')
endfunc

func! s:make()
    let s:lines   = readfile(g:project_make_dir . '/' . g:e_log_file)
    let s:lnum    = 0
    let s:len     = len(s:lines)
    let my_qf     = []
    let e_modules = {}
    let files     = []
    while s:lnum < s:len
	if s:lines[s:lnum] =~ '^Loading'
	    let f_line = ''
	    let j = 0
	    while s:lines[s:lnum] !~ '\<read\.\.\.\|^$' && j < 10
		let f_line .= ' ' . s:lines[s:lnum]
		let s:lnum += 1
		let j += 1
	    endwhile
	    let f_line = substitute(f_line, '^ Loading\|[()]\|\<imported by .*', '', 'g')
	    let f_list = split(f_line, ' + ')
	    for f in f_list
		let m = matchlist(f, '\v\f{-}(\w+)\.e')
		if m != []
                    let file = s:get_file_long(g:project_make_dir, m[0])
		    let e_modules[m[1]] = file
                    call add(files, file)
		endif
	    endfor
	elseif s:lines[s:lnum] =~ '\C^\s*\*\*\* \(Dut e\|E\)rror'
	    if s:lines[s:lnum] =~ ': Contradiction'
		let msg = s:get_text('^\s*that obey the constraints:', 0)
		let first = {'text': msg, 'type': 'C'}
		call add(my_qf, first)
		let s:lnum += 2
		let j = 1
		while 1
		    let errl = s:get_text('\v\@\w+\s*(,\s*)?$', 1)
		    let m = matchlist(errl, '\v(.*)<at line (\d+) in \@(\f+)')
		    call add(my_qf, {'filename': e_modules[m[3]], 'lnum': m[2], 'text': m[1], 'type': 'C', 'nr': j})
		    if errl !~ ',\s*$' | break | endif
		    let s:lnum += 1
		    let j += 1
		endwhile
		let first.filename = my_qf[-1].filename
		let first.lnum = my_qf[-1].lnum
	    else
		let msg = s:get_text('\sat line\>', 0)
		let s:lnum += 1
		let errl = s:get_text('@\w\|\.e', 1)
		let m = matchlist(errl, '\v\sat line (\d+) in (\@)?(\f+)')
		if m != []
		    let fn = (m[2] == '' ? s:get_file_long(g:project_make_dir, m[3]) : e_modules[m[3]])
		    call add(my_qf, {'filename': fn, 'lnum': m[1], 'text': msg, 'type': 'E'})
		endif
	    endif
	endif
	let s:lnum += 1
    endwhile
    call Project_add_files(files)
    unlet s:lines
    return my_qf
endfunc

"""""""""""""""""""""""""""""""
func! e#Project_init()
    let g:Project_make_post = function('s:make')
    echo g:project_type . ' init done!'
endfunc

func! e#Project_cleanup()
    echo g:project_type . ' cleanup done!'
endfunc
