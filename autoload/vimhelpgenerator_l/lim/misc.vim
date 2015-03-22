if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
scriptencoding utf-8
"=============================================================================
let s:TYPE_NR = type(0)

"Misc:
function! s:_get_rootpath_and_rootname_of(path) "{{{
  for dir in ['after', 'autoload', 'plugin', 'syntax', 'ftplugin', 'ftdetect']
    let findpath = finddir(dir, a:path. ';**/vimfiles;**/.vim')
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
function! vimhelpgenerator_l#lim#misc#get_cmdresults(cmd) "{{{
  let save_vfile = &verbosefile
  set verbosefile=
  redir => result
  silent! execute a:cmd
  redir END
  let &verbosefile = save_vfile
  return split(result, "\n")
endfunction
"}}}

function! vimhelpgenerator_l#lim#misc#get_sid(...) "{{{
  let path = !a:0 ? expand('%:p') : fnamemodify(expand(a:1), ':p')
  let snames = vimhelpgenerator_l#lim#misc#get_cmdresults('scriptnames')
  call map(snames, 'substitute(v:val, ''\s*\d*\s*:\s*\(.*\)'', ''\=expand(submatch(1))'', "")')
  let path = get(snames, 0, '')=~'\\' ? substitute(path, '/', '\\', 'g') : substitute(path, '\\', '/', 'g')
  let sid = index(snames, path, 0, 1)+1
  return sid
endfunction
"}}}
function! vimhelpgenerator_l#lim#misc#match_sids(pat) "{{{
  let snames = vimhelpgenerator_l#lim#misc#get_cmdresults('scriptnames')
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
function! vimhelpgenerator_l#lim#misc#get_scriptpath(sid) "{{{
  let snames = vimhelpgenerator_l#lim#misc#get_cmdresults('scriptnames')
  let path = substitute(get(snames, a:sid-1, ''), '^\s*\d\+:\s\+', '', '')
  return path=='' ? '' : fnamemodify(path, ':p')
endfunction
"}}}
function! vimhelpgenerator_l#lim#misc#get_scriptinfos(...) "{{{
  let pat = !a:0 ? expand('%') : type(a:1)==s:TYPE_NR ? '^\s*'.a:1.':' : escape(a:1, ' .\')
  let snames = vimhelpgenerator_l#lim#misc#get_cmdresults('scriptnames')
  let ret = []
  let idx = match(snames, pat)
  while idx!=-1
    call add(ret, snames[idx])
    let idx = match(snames, pat, idx+1)
  endwhile
  return ret
endfunction
"}}}

function! vimhelpgenerator_l#lim#misc#get_sfuncs(...) "{{{
  let path = a:0 ? expand(a:1) : expand('%')
  let sid = vimhelpgenerator_l#lim#misc#get_sid(path)
  if !sid
    if !(path==expand('%') || path==expand('%:p'))
      exe 'source' path
      let sid = vimhelpgenerator_l#lim#misc#get_sid(path)
    end
    if !sid
      return {}
    end
  end
  let prefix = '<SNR>'. sid. '_'
  let funcs = vimhelpgenerator_l#lim#misc#get_cmdresults('function')
  let filter_pat = '^\s*function '. prefix
  let map_pat = prefix. '\zs\w\+'
  let ret = {}
  for func in map(filter(funcs, 'v:val =~# filter_pat'), 'matchstr(v:val, map_pat)')
    let ret[func] = function(prefix. func)
  endfor
  return ret
endfunction
"}}}

function! vimhelpgenerator_l#lim#misc#hlecho(fmt, ...) "{{{
  for list in a:000
    exe 'echohl' get(list, 0, '')
    echon get(list, 1, '')
  endfor
  echoh
endfunction
"}}}


"======================================
"Data:
function! vimhelpgenerator_l#lim#misc#uniq(list) "{{{
  return s:newUniqfier(a:list).mill()
endfunction
"}}}


"======================================
"System:
function! vimhelpgenerator_l#lim#misc#path_encode(path) "{{{
  return substitute(a:path, '[=:/\\]', '\=get({"=": "==", ":": "=-"}, submatch(0), "=+")', 'g')
endfunction
"}}}
function! vimhelpgenerator_l#lim#misc#path_decode(fname) "{{{
  return substitute(a:fname, '==\|=+\|=-', '\={"==": "=", "=-": ":", "=+": "/"}[submatch(0)]', 'g')
endfunction
"}}}


function! vimhelpgenerator_l#lim#misc#infer_plugin_pathinfo(path) "{{{
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
