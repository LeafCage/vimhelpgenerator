if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
scriptencoding utf-8
"=============================================================================
let s:TYPE_NR = type(0)

"Misc:
function! s:_get_rootpath_and_rootname_of(path) "{{{
  let path = isdirectory(a:path) ? a:path : fnamemodify(a:path, ':h')
  for dir in ['after', 'autoload', 'plugin', 'syntax', 'ftplugin', 'ftdetect']
    let findpath = finddir(dir, path. ';**/vimfiles;**/.vim')
    if findpath == ''
      continue
    end
    let rootpath = fnamemodify(findpath, ':p:h:h')
    let rootname = fnamemodify(rootpath, ':t:r')
    if rootname =~# '^\%(vimfiles\|\.vim\)$'
      continue
    end
    return [rootpath, rootname]
  endfor
  return ['', '']
endfunction
"}}}
function! s:_get_actual_pluginname(rootpath) "{{{
  for expr in ['/plugin/*.vim', '/syntax/*.vim', '/autoload/*.vim']
    let file = glob(a:rootpath. expr)
    if file == '' || file =~ "\n"
      continue
    endif
    return fnamemodify(file, ':t:r')
  endfor
  return ''
endfunction
"}}}

let s:Uniqfier = {}
function! s:newUniqfier(list) "{{{
  let obj = copy(s:Uniqfier)
  let obj.list = a:list
  let obj.seens = {}
  return obj
endfunction
"}}}
function! s:Uniqfier._is_firstseen(str) "{{{
  let str = string(a:str)
  if has_key(self.seens, str)
    return 0
  end
  let self.seens[str] = 1
  return 1
endfunction
"}}}
function! s:Uniqfier.mill() "{{{
  return filter(self.list, 'self._is_firstseen(v:val)')
endfunction
"}}}


"=============================================================================
"Vim:
function! __vimhelpgenerator#lim#misc#viminfo_path() "{{{
  let path = matchstr(&viminfo, '^\%(.\+,\)\?n\zs.\+$')
  if path!=''
    return path
  else
    return (exists('$HOME') ? '$HOME' : exists('$VIM') ? '$VIM' : 'c:'). (has('win32') || has('win64') ? '/_viminfo' : '/.viminfo')
  end
endfunction
"}}}
function! __vimhelpgenerator#lim#misc#total_winheight() "{{{
  let ls = &laststatus>1 || &laststatus && winnr('$')>1
  let stal = &showtabline>1 || &showtabline && tabpagenr('$')>1
  return &lines - stal - ls - &l:cmdheight
endfunction
"}}}
function! __vimhelpgenerator#lim#misc#expand_keycodes(str) "{{{
  return substitute(a:str, '<\S\{-1,}>', '\=eval(''"\''. submatch(0). ''"'')', 'g')
endfunction
"}}}
function! __vimhelpgenerator#lim#misc#get_emptybufnr(...) "{{{
  let targnrs = range(bufnr('$'), 1, -1)
  if a:0
    let ignore_bufs = a:1
    call filter(targnrs, 'index(ignore_bufs, v:val)==-1')
  end
  for n in targnrs
    if bufname(n)=='' && match(getbufline(n, 1, '$'), '\S')==-1
      return n
    end
  endfor
  return 0
endfunction
"}}}


function! __vimhelpgenerator#lim#misc#get_cmdresults(cmd) "{{{
  let save_vfile = &verbosefile
  set verbosefile=
  redir => result
  silent! execute a:cmd
  redir END
  let &verbosefile = save_vfile
  return split(result, "\n")
endfunction
"}}}

function! __vimhelpgenerator#lim#misc#get_sid(...) "{{{
  let path = !a:0 ? expand('%:p') : fnamemodify(expand(a:1), ':p')
  let snames = __vimhelpgenerator#lim#misc#get_cmdresults('scriptnames')
  call map(snames, 'substitute(v:val, ''\s*\d*\s*:\s*\(.*\)'', ''\=expand(submatch(1))'', "")')
  let path = get(snames, 0, '')=~'\\' ? substitute(path, '/', '\\', 'g') : substitute(path, '\\', '/', 'g')
  let sid = index(snames, path, 0, 1)+1
  return sid
endfunction
"}}}
function! __vimhelpgenerator#lim#misc#match_sids(pat) "{{{
  let snames = __vimhelpgenerator#lim#misc#get_cmdresults('scriptnames')
  let sids = []
  let i = match(snames, escape(a:pat, ' .\'))+1
  while i
    call add(sids, i)
    let i += 1
    let i = match(snames, escape(a:pat, ' .\'), i)+1
  endwhile
  return sids
endfunction
"}}}
function! __vimhelpgenerator#lim#misc#get_scriptpath(sid) "{{{
  let snames = __vimhelpgenerator#lim#misc#get_cmdresults('scriptnames')
  let path = substitute(get(snames, a:sid-1, ''), '^\s*\d\+:\s\+', '', '')
  return path=='' ? '' : fnamemodify(path, ':p')
endfunction
"}}}
function! __vimhelpgenerator#lim#misc#get_scriptinfos(...) "{{{
  if a:0 > 1
    let expr = 'v:val =~ '''. escape(a:1, ' .\'). ''''
    for str in a:000[1:]
      let expr .= ' && v:val =~ '''. escape(str, ' .\'). ''''
    endfor
  else
    let pat = !a:0 ? expand('%') : type(a:1)==s:TYPE_NR ? '^\s*'.a:1.':' : escape(a:1, ' .\')
    let expr = 'v:val =~ pat'
  end
  return filter(__vimhelpgenerator#lim#misc#get_cmdresults('scriptnames'), expr)
endfunction
"}}}

function! __vimhelpgenerator#lim#misc#get_sfuncs(...) "{{{
  let path = a:0 ? expand(a:1) : expand('%')
  let sid = __vimhelpgenerator#lim#misc#get_sid(path)
  if !sid
    if !(path==expand('%') || path==expand('%:p'))
      exe 'source' path
      let sid = __vimhelpgenerator#lim#misc#get_sid(path)
    end
    if !sid
      return {}
    end
  end
  let prefix = '<SNR>'. sid. '_'
  let funcs = __vimhelpgenerator#lim#misc#get_cmdresults('function')
  let filter_pat = '^\s*function '. prefix
  let map_pat = prefix. '\zs\w\+'
  let ret = {}
  for func in map(filter(funcs, 'v:val =~# filter_pat'), 'matchstr(v:val, map_pat)')
    let ret[func] = function(prefix. func)
  endfor
  return ret
endfunction
"}}}


"======================================
"Data:
function! __vimhelpgenerator#lim#misc#uniq(list) "{{{
  return s:newUniqfier(a:list).mill()
endfunction
"}}}


"======================================
"System:
function! __vimhelpgenerator#lim#misc#path_encode(path) "{{{
  return substitute(a:path, '[=:/\\]', '\=get({"=": "==", ":": "=-"}, submatch(0), "=+")', 'g')
endfunction
"}}}
function! __vimhelpgenerator#lim#misc#path_decode(fname) "{{{
  return substitute(a:fname, '==\|=+\|=-', '\={"==": "=", "=-": ":", "=+": "/"}[submatch(0)]', 'g')
endfunction
"}}}


function! __vimhelpgenerator#lim#misc#infer_plugin_pathinfo(path) "{{{
  let [rootpath, rootname] = s:_get_rootpath_and_rootname_of(fnamemodify(expand(a:path), ':p'))
  if rootpath == ''
    return {}
  end
  let actualname = s:_get_actual_pluginname(rootpath)
  return {'root': rootpath, 'name': (actualname=='' ? rootname : actualname), 'rootname': rootname, 'actualname': actualname}
endfunction
"}}}

"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
