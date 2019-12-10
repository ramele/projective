" Projective generic project extension
" (Generic files collection + ctags support)
"""""""""""""""""""""""""""""""
if !exists('projective_ctags_cmd')
    let projective_ctags_cmd = ''
endif
if !exists('projective_ctags_lang')
    let projective_ctags_lang = 'C'
endif

func! s:set_make(clean)
    let s:clean = a:clean
    " force use console. take file list from the console:
    let projective_make_console = 1
endfunc

func! s:get_files_uniq()
    let files = getbufline('Console', 1, '$')
    let ofiles = []
    let fd = {}
    if !s:clean
        for f in Projective_get_files()
            call add(ofiles, f)
            let fd[f] = 1
        endfor
    endif
    for f in files
        let fs = simplify(f)
        if !has_key(fd, fs)
            call add(ofiles, fs)
            let fd[fs] = 1
        endif
    endfor
    call Projective_set_files(ofiles)
endfunc

func! s:generate_tags()
    if g:projective_ctags_cmd == ''
        return
    endif
    let g:cmd = g:projective_ctags_cmd . ' --languages=' . g:projective_ctags_lang . ' -f ' . Projective_path('tags') . ' -L ' . Projective_path('files.p')
    call Projective_run_job(g:cmd, {-> execute("echo 'tags done!'")}, 'tags')
endfunc

func! s:post_make()
    call s:get_files_uniq()
    call s:generate_tags()
endfunc

func! generic#Projective_init()
    let g:Projective_before_make = function('s:set_make')
    let g:Projective_after_make = function('s:post_make')
    let &tags = Projective_path('tags') . ',' . &tags
endfunc

func! generic#Projective_cleanup()
    unlet g:projective_ctags_cmd
    unlet g:projective_ctags_lang
    let &tags = substitute(&tags, Projective_path('tags') . ',', '', '')
endfunc
