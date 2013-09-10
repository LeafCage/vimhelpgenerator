"最新版のautoload/uptodate/uptodate.vimのみを読み込ませる "{{{
if exists('s:thisfile_updatetime')
  finish
endif
if !exists('g:uptodate_is_firstloaded')
  let g:uptodate_is_firstloaded = 1
  let s:firstloaded_is_this = 1
endif

let s:thisfile_updatetime = 1378827030
try
  if exists('g:uptodate_latesttime') && g:uptodate_latesttime >= s:thisfile_updatetime
    finish
  endif
  let g:uptodate_latesttime = s:thisfile_updatetime

  " NeoBundleLazyされてるplugin pathも 'runtimepath' に加える
  if !exists('g:uptodate_lazyrtp') && exists('*neobundle#config#get_neobundles')
    let g:uptodate_lazyrtp = join(map(filter(neobundle#config#get_neobundles(),'v:val.lazy'), 'v:val.rtp'), ',')
    let s:vimrt_idx = match(substitute(&rtp, '\\', '/', 'g'), substitute($VIMRUNTIME, '\\', '/', 'g'))-1
    let &rtp = &rtp[:(s:vimrt_idx)]. g:uptodate_lazyrtp. &rtp[(s:vimrt_idx):]
    unlet s:vimrt_idx
  endif
  let g:uptodate_lazyrtp = get(g:, 'uptodate_lazyrtp', '')

  if !exists('g:uptodate_is_runtiming')
    let g:uptodate_is_runtiming = 1
    runtime! autoload/uptodate/uptodate.vim
  endif
  if g:uptodate_latesttime > s:thisfile_updatetime
    finish
  endif
finally
  unlet s:thisfile_updatetime
  if exists('s:firstloaded_is_this')
    exe 'set rtp-='. g:uptodate_lazyrtp
    unlet g:uptodate_lazyrtp
    unlet g:uptodate_is_runtiming g:uptodate_latesttime g:uptodate_is_firstloaded s:firstloaded_is_this
  endif
endtry
"}}}

"======================================
if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
"=============================================================================
let s:TIMESTAMPROW_LAST = 35

let s:manager = {'paths': {}, 'latesttime': 0, 'is_runtiming': 0, 'addedlazyrtp': ''}
function! s:manager.reset() "{{{
  let self.paths = {}
  let self.latesttime = 0
  let self.is_runtiming = 0
  let self.addedlazyrtp = ''
endfunction
"}}}
let s:sfile = {}
function! s:manager.new_sfile(path) "{{{
  let sfile = {'_': self}
  let sfile.is_firstloaded = self.paths=={}
  let sfile.has_already_sourced = has_key(self.paths, a:path)
  let self.paths[a:path] = 1
  let sfile.path = a:path
  let sfile.updatetime = s:_get_uptodate_timestampline_num(a:path)
  let sfile.runtimecmd_args = substitute(a:path, '.*/\zeautoload/', '', '')
  call extend(sfile, s:sfile, 'keep')
  return sfile
endfunction
"}}}
function! s:sfile.is_older() "{{{
  if self._.latesttime >= self.updatetime
    return 1
  endif
  let self._.latesttime = self.updatetime
endfunction
"}}}
function! s:sfile.do_runtime() "{{{
  if self._.is_runtiming
    return
  endif
  let self._.is_runtiming = 1
  let self._.addedlazyrtp = s:_add_runtimepath_for_neobundlelazy()
  exe 'runtime! '. self.runtimecmd_args
endfunction
"}}}
function! s:sfile.is_older_afterall() "{{{
  return self._.latesttime > self.updatetime
endfunction
"}}}
function! s:sfile.update_loaded_var() "{{{
  let runtimecmd_argslist = split(self.runtimecmd_args)
  let thispat = substitute(self.path, '.*/\zeautoload/', '', '')
  let pat = substitute(get(runtimecmd_argslist, index(runtimecmd_argslist, thispat), ''), 'autoload/', '', '')
  let g:uptodate_loaded = get(g:, 'uptodate_loaded', {})
  let g:uptodate_loaded[pat] = get(g:uptodate_loaded, pat, {})
  let g:uptodate_loaded[pat].filepath = self.path
  let g:uptodate_loaded[pat].ver = self.updatetime
endfunction
"}}}
function! s:sfile.cleanup() "{{{
  if !self.is_firstloaded
    return
  endif
  exe 'set rtp-='. self._.addedlazyrtp
  call self._.reset()
endfunction
"}}}

"=============================================================================
"Main
"runtime!する そして読み込み中のスクリプトファイルが最新でない時は1を返す
function! uptodate#uptodate#isnot_this_uptodate(sfilepath) "{{{
  let sfile = s:manager.new_sfile(a:sfilepath)
  if sfile.has_already_sourced
    return 1
  endif
  try
    if sfile.is_older()
      return 1
    endif
    call sfile.do_runtime()
    if sfile.is_older_afterall()
      return 1
    endif
    call sfile.update_loaded_var()
  finally
    call sfile.cleanup()
  endtry
endfunction
"}}}

"再読み込みさせる :UptodateReloadManagedScripts
function! uptodate#uptodate#reload(sfilenames) "{{{
  let sfilenames = a:sfilenames==[] ? g:uptodate_filenamepatterns : a:sfilenames
  for sfilename in sfilenames
    exe 'runtime autoload/'. sfilename
  endfor
endfunction
"}}}

"他の全てのautoload/uptodate/uptodate.vimファイルの内、現在ファイルより古いものを
"現在ファイルで上書きする:UptodateApply
function! uptodate#uptodate#apply_uptodate_to_others() "{{{
  let paths = s:_get_paths('uptodate/uptodate.vim')
  let crrpath = expand('%:p')
  if crrpath !~# 'autoload/uptodate/uptodate.vim$'
    echohl WarningMsg| echo '"autoload/uptodate/uptodate.vim"の中で実行してください'| echohl NONE
    return
  endif
  if input('編集中のautoload/uptodate/uptodate.vimをこれより古い他の全てのautoload/uptodate/uptodate.vimに上書きしますか? [y/n] ') != 'y'
    return
  endif
  let crrftime = getftime(crrpath)
  let i = 0
  for path in filter(paths, 'v:val!=crrpath')
    if getftime(path) < crrftime
      call writefile(readfile(crrpath, 'b'), path, 'b')
      let i += 1
    endif
  endfor
  redraw
  echo '他の'. i. 'つのスクリプトが更新されました。'
endfunction
"}}}

"======================================
"autocmd
"edit時、最新版ならu/<C-r>Mappingを設定し、そうでなければ読込専用にする
function! uptodate#uptodate#forbid_editting_previousver(filepatterns) "{{{
  let paths = s:_get_paths(s:_select_crrpats(a:filepatterns))
  let latest = 0
  for path in paths
    let time = s:_get_uptodate_timestampline_num(path)
    let latest = time>latest ? time : latest
  endfor
  let crrtime = s:_get_uptodate_timestampline_num(expand('%:p'))
  if crrtime < latest
    echohl WarningMsg| echo 'uptodate: このファイルは最新版ではありません。たとえ更新してもuptodateからは無視されます。'| echohl NONE
    let b:uptodate_not_latest = 1
    setl ro
  else
    nnoremap <buffer>u    :<C-u>call <SID>_timestampskipping_undo('^\s*"UPTODATE: ')<CR>
    nnoremap <buffer><C-r>    :<C-u>call <SID>_timestampskipping_redo('^\s*"UPTODATE: ')<CR>
  endif
endfunction
"}}}
"write時、UPTODATE: . のタイムスタンプを発見、更新する
function! uptodate#uptodate#update_timestamp() "{{{
  if has_key(b:, 'uptodate_not_latest')
    return
  endif
  let lines = getline(1, s:TIMESTAMPROW_LAST)
  let timestamp_row = match(lines, 'UPTODATE:\s*\d*\.')+1
  if timestamp_row == 0
    return -1
  endif
  let updatetime = localtime()
  call setline(timestamp_row, substitute(lines[timestamp_row-1], 'UPTODATE:\s*\zs\d*\ze\.', updatetime, ''))
endfunction
"}}}
"write時、runtimepathの通った他の同名ファイルを更新する
function! uptodate#uptodate#update_otherfiles(filepatterns) "{{{
  if has_key(b:, 'uptodate_not_latest')
    return
  endif
  let crrpath = expand('%:p')
  let cellardir = get(g:, 'uptodate_cellardir', '')
  let cellardir = cellardir==''? '': fnamemodify(cellardir, ':p')
  if cellardir=='' || crrpath =~ cellardir
    let cellarpath = []
  else
    let crrdir = fnamemodify(crrpath, ':h:s?.*/autoload\ze\%(/\|$\)??')
    let cellardir = cellardir. crrdir
    if !isdirectory(cellardir)
      call mkdir(cellardir, 'p')
    endif
    let cellarpath = [cellardir. '/'. fnamemodify(crrpath, ':t')]
  endif
  let paths = s:_get_paths(s:_select_crrpats(a:filepatterns))
  let i = 0
  for path in filter(extend(paths, cellarpath), 'v:val!=crrpath')
    call writefile(readfile(expand('%:p'), 'b'), path, 'b')
    let i += 1
  endfor
  redraw
  echo 'uptodate: 他の'. i. 'つのスクリプトが更新されました。'
endfunction
"}}}
"autoload/uptodate.vimのwrite時、タイムスタンプ変数を更新する
function! uptodate#uptodate#update_uptodatefile() "{{{
  let lines = getline(1, s:TIMESTAMPROW_LAST)
  let timestamp_row = match(lines, '\s*let\s\+s:thisfile_updatetime')+1
  if timestamp_row == 0
    return -1
  endif
  let updatetime = localtime()
  call setline(timestamp_row, 'let s:thisfile_updatetime = '. updatetime)
endfunction
"}}}
"autoload/uptodate.vimの編集時、u/<C-r>で、無駄にタイムスタンプ更新変更を踏ませない
function! uptodate#uptodate#define_uptodate_localinterfaces() "{{{
  nnoremap <buffer>u    :<C-u>call <SID>_timestampskipping_undo('\s*let\s\+s:thisfile_updatetime')<CR>
  nnoremap <buffer><C-r>    :<C-u>call <SID>_timestampskipping_redo('\s*let\s\+s:thisfile_updatetime')<CR>
  command! -nargs=0 -buffer   UptodateApply    call uptodate#uptodate#apply_uptodate_to_others()
endfunction
"}}}



"=============================================================================
"NeoBundleLazyされていて 'runtimepath' に加わっていないパスを一時的に加える
function! s:_add_runtimepath_for_neobundlelazy() "{{{
  let addedlazyrtp = ''
  if exists('*neobundle#config#get_neobundles')
    let addedlazyrtp = join(map(filter(neobundle#config#get_neobundles(),'v:val.lazy'), 'v:val.rtp'), ',')
    let vimrt_idx = match(substitute(&rtp, '\\', '/', 'g'), substitute($VIMRUNTIME, '\\', '/', 'g'))-1
    let &rtp = &rtp[:vimrt_idx]. addedlazyrtp. &rtp[(vimrt_idx):]
  endif
  return addedlazyrtp
endfunction
"}}}
"==================
"uptodate#uptodate#isnot_this_uptodate()
function! s:_get_uptodate_timestampline_num(filepath) "{{{
  if !filereadable(a:filepath)
    return 0
  endif
  let lines = readfile(a:filepath, '', s:TIMESTAMPROW_LAST)
  let timestampline = matchstr(lines, 'UPTODATE:\s*\d\+\.')
  if timestampline == ''
    return 0
  endif
  return eval(matchstr(timestampline, 'UPTODATE:\s*\zs\d\+\ze\.'))
endfunction
"}}}
"==================
":UptodateReloadManagedScripts
function! uptodate#uptodate#_get_cmdcomplete_for_reload(arglead, cmdline, cursorpos) "{{{
  let libfiles = get(g:, 'uptodate_filenamepatterns', [])
  return filter(libfiles, 'v:val =~? a:arglead')
endfunction
"}}}
"==================
"autocmd
function! s:_get_paths(filepattern) "{{{
  if a:filepattern == ''
    return []
  endif
  let addedlazyrtp = s:_add_runtimepath_for_neobundlelazy()
  let paths = split(globpath(&rtp, 'autoload/'. a:filepattern), "\n")
  exe 'set rtp-='. addedlazyrtp
  call filter(paths, 'filereadable(v:val)')
  return paths
endfunction
"}}}
function! s:_select_crrpats(filepatterns) "{{{
  let filepatterns = copy(a:filepatterns)
  let crrpath = expand('%:p')
  let crrtail = fnamemodify(crrpath, ':t')
  call filter(filepatterns, 'fnamemodify(v:val, ":t")==crrtail')
  if filepatterns == []
    return ''
  endif

  let i = 1
  while filepatterns!=[]
    let save_filepatterns = copy(filepatterns)
    let mod = repeat(':h', i)
    let crrupperdir = fnamemodify(crrpath, mod. ':t')
    call filter(filepatterns, 'fnamemodify(v:val, mod. ":t")==crrupperdir')
    let i += 1
  endwhile
  return get(save_filepatterns, 0, '')
endfunction
"}}}
"uptodate#uptodate#define_timestampvarskipping_keymap()
function! s:_timestampskipping_undo(timestamp_pat) "{{{
  exe 'norm! '. v:count. 'u'
  while getline('.')=~a:timestamp_pat && undotree().seq_cur != 0
    undo
  endwhile
  norm! zv
endfunction
"}}}
function! s:_timestampskipping_redo(timestamp_pat) "{{{
  let save_view = winsaveview()
  exe 'norm!'. v:count. "\<C-r>"
  let seq_last = undotree().seq_last
  while getline('.')=~a:timestamp_pat && undotree().seq_cur != seq_last
    redo
  endwhile
  if undotree().seq_cur == seq_last
    call winrestview(save_view)
  endif
  norm! zv
endfunction
"}}}

"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
