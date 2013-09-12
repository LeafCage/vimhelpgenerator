"UPTODATE: 1378953596.
if lib#uptodate#isnot_this_uptodate(expand('<sfile>:p'))
  finish
endif
if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
"=============================================================================
let s:IGNORE_MONODIR = 'lib'
let s:pathholder = {'pluginname': '', 'realname': '', 'rootpath': '', 'is_monoplugin': 0}
"realname: _find_actualname()で見つける前の名前の方がプラグイン名としては適切
"   なものがあるのでこれに待避させる。
"is_monoplugin: 対象がpluginspluginならfileをうまく取ってこないことがあるので、
"   autoload/以下に1つしかdirがないときは全てのファイルを取得するようにする。
function! lib#vimelements#new_pathholder(...)
  let path = get(a:, 1, expand('%:p'))
  let collecttargets = get(a:, 2, [])
  let pathholder = {'is_failinit': 1}
  let pathholder.option = matchstr(collecttargets, 'unitesources')
  call extend(pathholder, s:pathholder, 'keep')
  call pathholder._set_rootpath_and_name(filereadable(path) ? fnamemodify(path, ':h') : path)
  call pathholder._find_actualname()
  call pathholder._judge_monoplugin()
  return pathholder
endfunction
function! s:pathholder.get_filepaths() "{{{
  let pluginpaths = globpath(self.rootpath. '/plugin',  '**/*.vim')
  if self.is_monoplugin
    let autoloadpaths = globpath(self.rootpath. '/autoload',  '**/*.vim')
  else
    let autoloadpaths = globpath(self.rootpath. '/autoload',  self.pluginname. '/**/*.vim')
    let autoloadpaths .= "\n".globpath(self.rootpath. '/autoload',   self.pluginname. '.vim')
    if self.option=='unitesources' && self.pluginname!='unite'
      let autoloadpaths .= "\n".globpath(self.rootpath. '/autoload',   'unite/sources/*.vim')
    endif
  endif
  let self.filepaths = filter(split(pluginpaths. "\n". autoloadpaths, '\n'), 'v:val!=""')
  return self.filepaths
endfunction
"}}}
function! s:pathholder._set_rootpath_and_name(path) "{{{
  for dir in ['after', 'autoload', 'plugin', 'syntax', 'ftplugin', 'ftdetect']
    let findpath = finddir(dir, a:path. ';**/vimfiles')
    if findpath == ''
      continue
    endif
    let self.rootpath = fnamemodify(findpath, ':p:h:h')
    let self.pluginname = fnamemodify(self.rootpath, ':t:r')
    if self.pluginname == 'vimfiles'
      continue
    endif
    let self.is_failinit = 0
    return
  endfor
endfunction
"}}}
function! s:pathholder._find_actualname() "{{{
  if self.is_failinit
    return
  endif
  for expr in ['/plugin/*.vim', '/syntax/*.vim', '/autoload/*.vim']
    let file = glob(self.rootpath. expr)
    if file == '' || file =~ "\n"
      continue
    endif
    let self.realname = self.pluginname
    let self.pluginname = fnamemodify(file, ':t:r')
    return
  endfor
endfunction
"}}}
function! s:pathholder._judge_monoplugin() "{{{
  if self.is_failinit
    return
  endif
  let dir = glob(self.rootpath. '/autoload/*/')
  if dir == '' || dir =~ "\n"
    return
  endif
  let dir = fnamemodify(dir, ':h:t')
  if dir =~# s:IGNORE_MONODIR
    return
  endif
  let self.is_monoplugin = 1
  "if self.realname==''
    "let self.realname = self.pluginname
    "let self.pluginname = dir
  "endif
endfunction
"}}}
"==================
let s:collector = {}
function! s:new_collector(path, rootpath)
  let collector = {'variables': {}, 'commands': {}, 'globalkeymappings': {}, 'localkeymappings': {}, 'keymappings_catalog': {'rhs': [], 'is_buflocal': [], 'modes': [], 'lhs': []}, 'functions': {}, 'autocmds': [], 'unitesources': []}
  let collector.path = fnamemodify(a:path, ':p')
  let collector.autoload_prefix = s:_autoload_prefix(a:path, a:rootpath)
  let collector.lines = filter(readfile(a:path), 'v:val !~ "^\\s*$"')
  call s:_exclude_commentline(collector.lines)
  call extend(collector, s:collector, 'keep')
  return collector
endfunction
function! s:_autoload_prefix(path, rootpath) "{{{
  let localpath = substitute(a:path, a:rootpath. '/', '', '')
  if localpath !~ '^autoload'
    return ''
  endif
  return fnamemodify(localpath, ':r:s?^autoload/??:gs?/?#?'). '#'
endfunction
"}}}
function! s:_exclude_commentline(lines) "{{{
  let i = 0
  let len = len(a:lines)
  while i < len
    if a:lines[i] !~ '^\s*"'
      let i += 1
      continue
    endif
    call remove(a:lines, i)
    let len -= 1
    while get(a:lines, i, '') =~ '^\s*\\'
      call remove(a:lines, i)
      let len -= 1
    endwhile
  endwhile
endfunction
"}}}
function! s:collector.collect(kind) "{{{
  let onetimefuncname = '_add_'. a:kind. '_onetime'
  if has_key(self, onetimefuncname)
    call self[onetimefuncname]()
  endif
  let [s:_var_scope_is_global, s:_aug_scope_name] = [1, 'END']
  let funcname = '_add_'. a:kind
  if !has_key(self, funcname)
    return
  endif
  let i = 0
  let len = len(self.lines)
  while i < len
    call self[funcname](i)
    let i += 1
  endwhile
endfunction
"}}}
function! s:collector._add_variables(idx) "{{{
  let linestr = self.lines[a:idx]
  let autoloadvar = self.autoload_prefix=='' ? '' : matchstr(linestr, 'let\s\+\%(g:\)\?\zs'. self.autoload_prefix. '\S\+\ze\+\s*=')
  if autoloadvar != ''
    call self.__add_variables(autoloadvar, a:idx)
  endif

  let s:_var_scope_is_global = linestr=~#'^\s*endf\%[unction]\>' ? 1 : linestr=~#'^\s*fu\%[nction]!\?\_s' ? 0 : s:_var_scope_is_global
  let pat = s:_var_scope_is_global ? 'g:\w\+\|let\s\+\zs\w[^:]\w*' : 'g:\w\+'
  let i = 1
  while 1
    let var = matchstr(linestr, pat, 0, i)
    let i+=1
    if var == ''
      return
    elseif var =~# 'g:loaded_'
      continue
    endif
    call self.__add_variables(var, a:idx)
  endwhile
endfunction
"}}}
function! s:collector._add_commands(idx) "{{{
  let linestr = self.lines[a:idx]
  if linestr !~# '^\s*com\%[mand]!\?\>'
    return
  endif
  let linestr = s:_join_line_continuation(self.lines, a:idx)
  let linestr = s:_remove_nl_for_line_continuation(linestr)
  let commandname = s:_commandname(linestr)
  let s:_command_order += has_key(self.commands, commandname) ? 0 : 1
  let self.commands[commandname] = extend(s:_commandattr(linestr), {'order': s:_command_order})
endfunction
"}}}
function! s:collector._add_keymappings(idx) "{{{
  let mapcommand = s:_mapcommand(self.lines[a:idx])
  if mapcommand == ''
    return
  endif
  let linestr = s:_join_line_continuation(self.lines, a:idx)
  let linestr = s:_remove_nl_for_line_continuation(linestr)
  let [mode, remap] = s:_keymap_mode(mapcommand)
  let [options, lhs, rhs] = s:_keymap_elements(linestr, mapcommand)
  if lhs == '' || rhs == ''
    return | "s:_mapcommand()が誤爆したとき用
  endif
  let keymappings = options.is_buflocal ? self.localkeymappings : self.globalkeymappings
  let s:_keymapping_order += has_key(keymappings, lhs) ? 0 : 1
  let keymappings[lhs] = get(keymappings, lhs, {'common': {'is_defaultmapping': 0, 'is_local': options.is_buflocal, 'order': s:_keymapping_order}})
  for m in ['n', 'i', 'c', 'o', 'x', 's']
    if !mode[m]
      continue
    endif
    let keymappings[lhs][m] = get(keymappings[lhs], m, s:_neutral_keymappingmodes())
    call add(keymappings[lhs][m].rhs, rhs)
  endfor
  call add(self.keymappings_catalog.rhs, rhs)
  call add(self.keymappings_catalog.is_buflocal, options.is_buflocal)
  call add(self.keymappings_catalog.modes, keys(filter(mode, 'v:val==1')))
  call add(self.keymappings_catalog.lhs, lhs)
endfunction
"}}}
function! s:collector._add_keymappings_onetime() "{{{
  let idx = match(self.lines, 'textobj#user#plugin')
  if idx==-1
    return
  endif
endfunction
"}}}
function! s:collector._add_functions(idx) "{{{
  let linestr = self.lines[a:idx]
  let func = matchlist(linestr, '^\s*fu\%[nction]!\?\s\+\(.\+\)(\(.*\))')
  if func == []
    return
  endif
  let [funcname, param] = func[1:2]
  let self.functions[funcname] = {'param': substitute(substitute(param, '\w\+\|\.\.\.', '{\0}', 'g'), '_', '-', 'g')}
  let self.functions[funcname].is_global = funcname =~ '^\u\|^[^s]:'. (self.autoload_prefix == '' ? '' : '\|'. self.autoload_prefix)
  let self.functions[funcname].is_dict = funcname =~ '\.\|\['
endfunction
"}}}
function! s:collector._add_autocmds(idx) "{{{
  let linestr = self.lines[a:idx]
  let s:_aug_scope_name = linestr=~'\<aug\%[roup]\>' ? matchstr(linestr, 'aug\%[roup]\s\+\zs\w\+') : s:_aug_scope_name
  let s:_aug_scope_name = s:_aug_scope_name=~?'end' ? 'END' : s:_aug_scope_name
  if linestr !~# '\<au\%[tocmd]\s'
    return
  endif
  let linestr = s:_join_line_continuation(self.lines, a:idx)
  let linestr = s:_remove_nl_for_line_continuation(linestr)
  let autocmd_param = s:_au_purser(linestr)
  if autocmd_param!={}
    call add(self.autocmds, autocmd_param)
  endif
endfunction
"}}}
function! s:collector._add_unitesources(idx) "{{{
  let linestr = self.lines[a:idx]
  let sourcename = matchstr(linestr, 'fu\%[nction]!\?\s\+unite#sources#\zs\w\+\ze#define()')
  if sourcename!=''
    call add(self.unitesources, sourcename)
  endif
endfunction
"}}}
function! s:collector._add_unitesources_onetime() "{{{
  let idxes = []
  let idx = match(self.lines, 'unite#define_source', 0)
  while idx!=-1
    call add(idxes, idx)
    let idx += 1
    let idx = match(self.lines, 'unite#define_source', idx)
  endwhile
  if idxes==[]
    return
  endif
  for idx in idxes
    let sourcevar = matchstr(self.lines[idx], 'unite#define_source(\s*\zs\S\+\ze\s*)')
    let sourcename = matchstr(self.lines, '^\s*let\s\+'. sourcevar. '\%(.name\|\[["'']name["'']\]\)\s*=')
    if sourcename==''
      let idx = match(self.lines, '^\s*let\s\+'. sourcevar. '\s*=')
      let linestr = s:_join_line_continuation(self.lines, idx)
      let linestr = s:_remove_nl_for_line_continuation(linestr)
      let sourcename = matchstr(linestr, '^\s*let\s\+'. sourcevar. '\s*=\s*{.*["'']name["'']\s*:\s*["'']\zs[a-z0-9_/]')
    else
      let sourcename = matchstr(sourcename, '^\s*let\s\+'. sourcevar. '\%(.name\|\[["'']name["'']\]\)\s*=\s*["'']\zs[a-z0-9_/]\+')
    endif
    if sourcename==''
      echohl WarningMsg| echo 'unite-source-nameの取得に失敗しました。'| echohl NONE
    else
      call add(self.unitesources, sourcename)
    endif
  endfor
endfunction
"}}}
"==================
let s:elementholder = {}
function! s:new_elementholder()
  let elementholder = {'keymappings_catalog': {'rhs': [], 'is_buflocal': [], 'modes': [], 'lhs': []}, 'elements': {'variables': {}, 'commands': {}, 'globalkeymappings': {}, 'localkeymappings': {}, 'functions': {}, 'autocmds': [], 'unitesources': []}}
  call extend(elementholder, s:elementholder, 'keep')
  return elementholder
endfunction
function! s:elementholder.eat(collector) "{{{
  call map(self.elements.variables, 's:_combine_variablesvals(a:collector.variables, v:key, v:val)')
  call extend(self.elements.variables, a:collector.variables, 'keep')
  try
    call extend(self.elements.commands, a:collector.commands, 'error')
  catch /E737/
    echohl WarningMsg| echom '同名のコマンドが複数定義されています。'. v:exception| echohl NONE
    call extend(self.elements.commands, a:collector.commands, 'keep')
  endtry
  call map(self.elements.localkeymappings, 's:_combine_keymapping(a:collector.localkeymappings, v:key, v:val)')
  call extend(self.elements.localkeymappings, a:collector.localkeymappings, 'keep')
  call map(self.elements.globalkeymappings, 's:_combine_keymappings(a:collector.globalkeymappings, v:key, v:val)')
  call extend(self.elements.globalkeymappings, a:collector.globalkeymappings, 'keep')
  call extend(self.keymappings_catalog.rhs, a:collector.keymappings_catalog.rhs)
  call extend(self.keymappings_catalog.is_buflocal, a:collector.keymappings_catalog.is_buflocal)
  call extend(self.keymappings_catalog.modes, a:collector.keymappings_catalog.modes)
  call extend(self.keymappings_catalog.lhs, a:collector.keymappings_catalog.lhs)
  call extend(self.elements.functions, a:collector.functions, 'keep')
  call extend(self.elements.autocmds, a:collector.autocmds)
  call extend(self.elements.unitesources, a:collector.unitesources)
endfunction
"}}}
function! s:elementholder.set_default_keymappings() "{{{
  for lhs in keys(self.elements.globalkeymappings) + keys(self.elements.localkeymappings)
    if lhs =~? '^<Plug>'
      call s:_find_pluginmapping_from_rhss(lhs, self.elements.globalkeymappings, self.elements.localkeymappings, self.keymappings_catalog)
    endif
  endfor
  unlet self.keymappings_catalog
endfunction
"}}}
function! s:elementholder.eat_pathholder(pathholder) "{{{
  let self.pluginname = a:pathholder.pluginname
  let self.realname = a:pathholder.realname
  let self.rootpath = a:pathholder.rootpath
  let self.filepaths = a:pathholder.filepaths
  let self.is_monoplugin = a:pathholder.is_monoplugin
endfunction
"}}}
function! s:elementholder.untap() "{{{
  unlet self.eat
  unlet self.set_default_keymappings
  unlet self.eat_pathholder
  unlet self.untap
endfunction
"}}}

"========================================================
"Main
"lib#vimelements#collect()
"lib#vimelements#collect(String path)
"lib#vimelements#collect(Dictionary pathholder)
"lib#vimelements#collect(List collecttargets)
"lib#vimelements#collect(String path, List collecttargets)
"lib#vimelements#collect(Dictionary pathholder, List collecttargets)
function! lib#vimelements#collect(...)
  let [pathholder, collecttargets] = s:_collect_varargs(a:000)
  let elementholder = s:new_elementholder()
  let [s:_var_order, s:_command_order, s:_keymapping_order] = [0, 0, 0]
  let s:AU_PURSEPAT = s:_AU_PURSEPAT()
  for scriptpath in pathholder.get_filepaths()
    let collector = s:new_collector(scriptpath, pathholder.rootpath)
    for target in collecttargets
      call collector.collect(target)
    endfor
    call elementholder.eat(collector)
  endfor
  unlet! s:_var_order s:_command_order s:_keymapping_order s:_var_scope_is_global s:AU_PURSEPAT
  call elementholder.set_default_keymappings()
  call elementholder.eat_pathholder(pathholder)
  call elementholder.untap()
  return elementholder
endfunction


"======================================
"main
function! s:_collect_varargs(varargs) "{{{
  let len = len(a:varargs)
  let type0 = type(get(a:varargs, 0, 0))
  let DEFAULT_COLLECTTARGETS = ['variables', 'commands', 'keymappings', 'functions', 'autocmds']
  if len>=2
    return type0==type({}) ? [a:varargs[0], a:varargs[1]] : [lib#vimelements#new_pathholder(a:varargs[0], a:varargs[1]), a:varargs[1]]
  elseif len
    return type0==type([]) ? [lib#vimelements#new_pathholder(expand('%:p'), a:varargs[0]), a:varargs[0]] : type0==type({}) ? [a:varargs[0], DEFAULT_COLLECTTARGETS] : [lib#vimelements#new_pathholder(a:varargs[0]), DEFAULT_COLLECTTARGETS]
  else
    return [lib#vimelements#new_pathholder(), DEFAULT_COLLECTTARGETS]
  endif
endfunction
"}}}
"==================
"common
function! s:_neutral_keymappingmodes() "{{{
  return {'rhs': [], 'defaultmappings': [], 'localdefaultmappings': []}
endfunction
"}}}
"==================
"collector
function! s:_join_line_continuation(lines, idx) "{{{
  let linestr = a:lines[a:idx]
  let i = 1
  while get(a:lines, a:idx+i, '') =~ '^\s*\\'
    let linestr .= "\n". get(a:lines, a:idx+i, '')
    let i += 1
  endwhile
  return linestr
endfunction
"}}}
function! s:_remove_nl_for_line_continuation(linestr) "{{{
  return substitute(a:linestr, '\s*\n\s*\\', ' ', 'g')
endfunction
"}}}
"variables
function! s:collector.__add_variables(var, idx) "{{{
  let vallist = s:_add_var(self.variables, a:var)
  let val = matchstr(self.lines[a:idx], 'let\s\+'. a:var. '\s*\zs=.*')
  if val != ''
    let val = s:_join_val_line_continuation(val, self.lines, a:idx)
    call s:_add_val(vallist, val, a:var)
  endif
endfunction
"}}}
function! s:_add_var(variables, var) "{{{
  let s:_var_order += has_key(a:variables, a:var) ? 0 : 1
  let a:variables[a:var] = get(a:variables, a:var, {'vals': [], 'is_dict': 0, 'order': s:_var_order})
  return a:variables[a:var]
endfunction
"}}}
function! s:_join_val_line_continuation(val, lines, idx) "{{{
  let val = substitute(a:val, '^=\s*', '', '')
  let i = 1
  while get(a:lines, a:idx+i, '') =~ '^\s*\\'
    let val .= "\n". get(a:lines, a:idx+i, '')
    let i += 1
  endwhile
  return val
endfunction
"}}}
function! s:_add_val(vallist, val, var) "{{{
  let val = a:val
  let jval = substitute(val, '\s*\n\s*\\\s*', ' ', 'g')
  if jval =~ 'get(\s*g:,\s*["'']'. substitute(a:var, 'g:', '', ''). '["''],\s*.\+)\|exists(\s*["'']'. a:var. '["'']\s*)'
    let jval = substitute(jval, 'get(\s*g:,\s*["'']'. substitute(a:var, 'g:', '', ''). '["''],\s*\(.\+\))', '\1', '')
    let jval = substitute(jval, 'exists(\s*["'']\+'. a:var. '["'']\+\s*)\s*?\s*'. a:var. '\s*:\s*', '', '')
    let jval = substitute(jval, '!exists(\s*["'']'. a:var. '["'']\s*)\s*?\s*\(.*\)\s*:\s*'. a:var, '\1', '')
    let val = jval
  endif
  if a:val =~ '^{'
    let a:vallist.is_dict = 1
  endif
  if index(a:vallist.vals, val) == -1
    call add(a:vallist.vals, val)
  endif
endfunction
"}}}
"commands
function! s:_commandname(linestr) "{{{
  return matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-\S\+\s\+\)*\zs\u\S*\ze')
endfunction
"}}}
function! s:_commandattr(linestr) "{{{
  let attr = {'nargs': '', 'range': {}, 'is_bang': 0, 'is_register': 0, 'is_buflocal': 0, 'complete': ''}
  let attr.nargs = matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-nargs=\zs.')
  let attr.range.count = matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-count\s') ? 0 : matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-count=\zs\d\+')
  let attr.range.range = matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-range\s') ? 'current line' : matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-range=\zs\S\+')
  let attr.complete = matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-complete=\zs\S\+\ze\s')
  let attr.is_bang = a:linestr =~ 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-bang'
  let attr.is_register = a:linestr =~ 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-register'
  let attr.is_buflocal = a:linestr =~ 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-buffer'
  return attr
endfunction
"}}}
"keymappings
function! s:_mapcommand(linestr) "{{{
  return matchstr(a:linestr, '^\s*\%(sil\%[ent!]\s\+\)*\zs\%([nvxoic]m\%[ap]\|s\?map!\?\|[oic]\?no\%[remap]!\?\|[nvx]n\%[oremap]\|snor\%[emap]\)\ze\s')
endfunction
"}}}
function! s:_keymap_mode(mapcommand) "{{{
  let mode = {'n': 0, 'i': 0, 'c': 0, 'o': 0, 'x': 0, 's': 0}
  let remap = a:mapcommand =~ '[oicnvxs]n\|no' ? 0 : 1
  let modestrlist = remap ? matchlist(a:mapcommand, '\(\l\?\)m\%[ap]\(!\?\)')[1:2] : matchlist(a:mapcommand, '\(\l\?\)n\%[oremap]\(!\?\)')[1:2]
  call s:__set_mode(mode, modestrlist)
  return [mode, remap]
endfunction
"}}}
function! s:__set_mode(mode, modestrlist) "{{{
  if a:modestrlist[1] == '!'
    let a:mode.i = 1
    let a:mode.c = 1
  elseif a:modestrlist[0] == ''
    let a:mode.n = 1
    let a:mode.x = 1
    let a:mode.s = 1
    let a:mode.o = 1
  elseif a:modestrlist[0] == 'v'
    let a:mode.x = 1
    let a:mode.s = 1
  else
    let a:mode[a:modestrlist[0]] = 1
  endif
endfunction
"}}}
function! s:_keymap_elements(linestr, mapcommand) "{{{
  let options = {'is_buflocal': 0, 'is_silent': 0, 'is_unique': 0, 'is_expr': 0}
  let optionsstr = matchstr(a:linestr, '\%(\%(<buffer>\|<silent>\|<expr>\|<unique>\|<special>\|<script>\)\s*\)\+')
  let options.is_buflocal = optionsstr=~'<buffer>'
  let options.is_silent = optionsstr=~'<silent>'
  let options.is_unique = optionsstr=~'<unique>'
  let options.is_expr = optionsstr=~'<expr>'

  let lhs = matchstr(a:linestr, a:mapcommand. '\s\+'. optionsstr. '\zs\S\+')
  let rhs = matchstr(a:linestr, a:mapcommand. '\s\+'. optionsstr. escape(lhs, '~$.*\'). '\s\+\zs.\+')
  let lhs = s:_substitute_uppercase_sameformat(lhs)
  let rhs = s:_substitute_uppercase_sameformat(rhs)
  return [options, lhs, rhs]
endfunction
"}}}
function! s:_substitute_uppercase_sameformat(str) "{{{
  let str = substitute(substitute(a:str, '<\c\([CSM]-\)\?\(\a\{2}\)>', '<\U\1\2\E>', 'g'), '\c<\([CSM]-\)\?up>', '<\u\1Up>', 'g')
  return substitute(str, '\c<\([CSM]-\)\?\(\a\)\(\a\{2,}\)>', '<\u\1\u\2\L\3\E>', 'g')
endfunction
"}}}
"autocmds
function! s:_AU_PURSEPAT() "{{{
  let AU_EVENTPAT = '\%(BufNew\%(File\)\?\|Buf\%(Read\|Write\)\%(Pre\|Post\|Cmd\)\?\|\%(BufFile\|StdinRead\|QuickFixCmd\)P\%(re\|ost\)\|\%(Buf\%(Win\)\?\|Win\|Cmdwin\|Tab\)\%(Enter\|Leave\)\|Buf\%(Add\|Create\|Delete\|Wipeout\|Unload\|Hidden\)\|File\%(Read\|Write\|Append\)\%(Pre\|Post\|Cmd\)\|Filter\%(Read\|Write\)P\%(re\|ost\)\|\%(Encoding\|Term\)Changed\|Vim\%(Enter\|Resized\)\|GUI\%(Enter\|Failed\)\|VimLeave\%(Pre\)\?\|FileChanged\%(RO\|Shell\%(Post\)\?\)\|Shell\%(Cmd\|Filter\)Post\|Insert\%(Enter\|Change\|Leave\|CharPre\)\|Cursor\%(HoldI\?\|MovedI\?\)\|Focus\%(Gained\|Lost\)\|Source\%(Pre\|Cmd\)\|ColorScheme\|CompleteDone\|FileType\|FuncUndefined\|RemoteReply\|SessionLoadPost\|SpellFileMissing\|SwapExists\|Syntax\|TermResponse\|MenuPopup\|TextChangedI\?\|QuitPre\|User\)'
  return 'au\%[tocmd]\s\+\%(\(\S\+\)\s\+\)\?\(\%('. AU_EVENTPAT. ',\?\)\+\)\s\+\(\S\+\)\s\+\%(nested\s\+\)\?\(\S.\+\)'
endfunction
"}}}
function! s:_au_purser(linestr) "{{{
  let autocmdlist = matchlist(a:linestr, s:AU_PURSEPAT)
  return autocmdlist==[] ? {} : {'events': split(autocmdlist[2], ','), 'patterns': s:_au_join_escapedcomma_pat(split(autocmdlist[3], ',')), 'group': autocmdlist[1]=='' ? s:_aug_scope_name : autocmdlist[1], 'cmd': autocmdlist[4]}
endfunction
"}}}
function! s:_au_join_escapedcomma_pat(patterns) "{{{
  let len = len(a:patterns)
  if len<2
    return a:patterns
  endif
  let i = 0
  while i < len
    if a:patterns[i]=~'\\$' && i < len-1
      let a:patterns[i] .= a:patterns[i+1]
      call remove(a:patterns, i+1)
      let len -=1
    else
      let i+=1
    endif
  endwhile
  return a:patterns
endfunction
"}}}
"==================
"elementholder
"eat()
function! s:_combine_variablesvals(collectorvariables, var, elm) "{{{
  if has_key(a:collectorvariables, a:var)
    call extend(a:elm.vals, a:collectorvariables[a:var].vals)
  endif
  return a:elm
  "elm = {'vals': [], 'is_dict': 0}
endfunction
"}}}
function! s:_combine_keymappings(collectorkeymappings_lhs, lhs, elm) "{{{
  if has_key(a:collectorkeymappings_lhs, a:lhs)
    call extend(a:elm, a:collectorkeymappings_lhs[a:lhs])
  endif
  return a:elm
endfunction
"}}}
function! s:_combine_keymapping(collectorkeymappings, lhs, modes) "{{{
  if !has_key(a:collectorkeymappings, a:lhs)
    return a:modes
  endif
  for m in ['n', 'i', 'x', 's', 'o', 'c']
    if has_key(a:collectorkeymappings[a:lhs], m)
      let a:modes[m] = get(a:modes, m, s:_neutral_keymappingmodes())
      call extend(a:modes[m].rhs, a:collectorkeymappings[a:lhs][m].rhs)
    endif
  endfor
  return a:modes
endfunction
"}}}
"set_default_keymappings()
function! s:_find_pluginmapping_from_rhss(pluginmapping, globalkeymappings, localkeymappings, keymappings_catalog) "{{{
  let idx = match(a:keymappings_catalog.rhs, a:pluginmapping, 0)
  while idx!=-1
    let keymappings = a:keymappings_catalog.is_buflocal[idx] ? a:localkeymappings : a:globalkeymappings
    let keymappings[a:keymappings_catalog.lhs[idx]].common.is_defaultmapping = 1
    let keymappings = has_key(a:localkeymappings, a:pluginmapping) ? a:localkeymappings : a:globalkeymappings
    for m in a:keymappings_catalog.modes[idx]
      if !has_key(keymappings[a:pluginmapping], m)
        continue
      endif
      if a:keymappings_catalog.is_buflocal[idx]
        call s:_add_without_duplicate(keymappings[a:pluginmapping][m].localdefaultmappings, a:keymappings_catalog.lhs[idx])
      else
        call s:_add_without_duplicate(keymappings[a:pluginmapping][m].defaultmappings, a:keymappings_catalog.lhs[idx])
      endif
    endfor
    let idx += 1
    let idx = match(a:keymappings_catalog.rhs, a:pluginmapping, idx)
  endwhile
endfunction
"}}}
function! s:_add_without_duplicate(list, expr) "{{{
  if index(a:list, a:expr) == -1
    call add(a:list, a:expr)
  endif
endfunction
"}}}

"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
