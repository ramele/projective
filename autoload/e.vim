" Projective e (Specman) extension
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

func! s:read_sn_logfile()
    let s:lines   = readfile(g:projective_make_dir . '/' . g:projective_e_log_file)
    let s:lnum    = 0
    let s:len     = len(s:lines)
    let my_qf     = []
    let e_modules = {}
    let files     = []
    while s:lnum < s:len
	if s:lines[s:lnum] =~ '^Loading'
	    let msg = s:get_text('\<read\.\.\.\|^$', 0)
	    let msg = substitute(msg, '^\s*Loading\|[()]\|\<imported by .*', '', 'g')
	    let f_list = split(msg, ' + ')
	    for f in f_list
		let m = matchlist(f, '\v\f{-}(\w+)\.e')
		if m != []
                    let file = s:get_file_long(g:projective_make_dir, m[0])
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
                    if msg =~ 'Dut error'
                        let s:lnum += 1
                        let msg = s:get_text('^----*$', 0)
                    endif
		    let fn = (m[2] == '' ? s:get_file_long(g:projective_make_dir, m[3]) : e_modules[m[3]])
		    call add(my_qf, {'filename': fn, 'lnum': m[1], 'text': msg, 'type': 'E'})
		endif
	    endif
	endif
	let s:lnum += 1
    endwhile
    if empty(my_qf) || empty(Projective_get_files())
        call Projective_set_files(files)
    endif
    unlet s:lines
    return my_qf
endfunc

let s:e_parser = resolve(globpath(&rtp, 'languages/e/e_parser.vim'))
if s:e_parser != ''
    exe 'source' s:e_parser
endif

"""""""""""""""""""""""""""""""
func! e#Projective_init()
    let g:Projective_after_make = function('s:read_sn_logfile')
    if s:e_parser != ''
        call E_parser_init()
    endif
"    echo g:projective_project_type . ' init done!'
endfunc

func! e#Projective_cleanup()
    if s:e_parser != ''
        call E_parser_cleanup()
    endif
"    echo g:projective_project_type . ' cleanup done!'
endfunc

