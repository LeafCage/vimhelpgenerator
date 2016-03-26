scriptencoding utf-8
if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
"=============================================================================
let s:TYPE_STR = type('')
let s:TYPE_LIST = type([])
let s:NEUTRAL_KEYMAPPINGMODES = {}
let s:AUTOCMDS_PAT = 'au\%[tocmd]\s\+\%(\(\S\+\)\s\+\)\?\(\%('.
  \ '\%(
  \Buf\%(Add\|Create\|Delete\|Enter\|FileP\%(ost\|re\)\|Hidden\|Leave\|New\%(File\)\?\|Read\%(\%(Cmd\|P\%(ost\|re\)\)\)\?\|Unload\|W\%(i\%(n\%(Enter\|Leave\)\|peout\)\|rite\%(\%(Cmd\|P\%(ost\|re\)\)\)\?\)\)
  \\|C\%(mdwin\%(Enter\|Leave\)\|o\%(lorScheme\|mpleteDone\)\|ursor\%(HoldI\?\|MovedI\?\)\)
  \\|F\%(il\%(e\%(Append\%(Cmd\|P\%(ost\|re\)\)\|Changed\%(RO\|Shell\%(Post\)\?\)\|Read\%(Cmd\|P\%(ost\|re\)\)\|Type\|Write\%(Cmd\|P\%(ost\|re\)\)\)\|ter\%(ReadP\%(ost\|re\)\|WriteP\%(ost\|re\)\)\)\|ocus\%(Gained\|Lost\)\|uncUndefined\)
  \\|Insert\%(Cha\%(nge\|rPre\)\|Enter\|Leave\)
  \\|Qui\%(ckFixCmdP\%(ost\|re\)\|tPre\)
  \\|S\%(essionLoadPost\|hell\%(CmdPost\|FilterPost\)\|ource\%(Cmd\|Pre\)\|pellFileMissing\|tdinReadP\%(ost\|re\)\|wapExists\|yntax\)
  \\|T\%(ab\%(Enter\|Leave\)\|erm\%(Changed\|Response\)\)
  \\|Vim\%(Enter\|Leave\%(Pre\)\?\|Resized\)
  \\|EncodingChanged\|GUI\%(Enter\|Failed\)\|MenuPopup\|RemoteReply\|User\|Win\%(Enter\|Leave\)
  \\)'
  \ . ',\?\)\+\)\s\+\(\S\+\)\s\+\%(nested\s\+\)\?\(\S.\+\)'


"======================================
"main
function! s:init_args(variadic) "{{{
  let collecttargets = ['variables', 'commands', 'keymappings', 'functions', 'autocmds']
  for arg in a:variadic
    let type = type(arg)
    if type==s:TYPE_STR
      let {exists('pluginroot') ? 'pluginname' : 'pluginroot'} = arg
    elseif type==s:TYPE_LIST
      let collecttargets = arg
    end
    unlet arg
  endfor
  if get(l:, 'pluginroot', '')==''
    let inference = __vimhelpgenerator#lim#misc#infer_plugin_pathinfo(expand('%'))
    if inference=={}
      return {}
    end
    let pluginroot = inference.root
  end
  if get(l:, 'pluginname', '')==''
    if !exists('inference')
      let inference = __vimhelpgenerator#lim#misc#infer_plugin_pathinfo(pluginroot)
      if inference=={}
        return {}
      end
    end
    let pluginname = inference.name
  end
  return {'root': pluginroot, 'name': pluginname, 'collecttargets': collecttargets}
endfunction
"}}}
function! s:get_paths(root, pluginname, collect_unitesources) "{{{
  let pluginpaths = globpath(a:root. '/plugin',  '**/*.vim')
  let audir = glob(a:root. '/autoload/*/')
  if audir == '' || audir =~ "\n"
    let autoloadpaths = globpath(a:root. '/autoload',  a:pluginname. '/**/*.vim')
    let path = a:root.'/autoload/'.a:pluginname.'.vim'
    let autoloadpaths .= filereadable(path) ? "\n". path : ''
    if a:collect_unitesources && a:pluginname!='unite'
      let autoloadpaths .= "\n".globpath(a:root. '/autoload',   'unite/sources/*.vim')
    endif
  else
    let autoloadpaths = globpath(a:root. '/autoload',  '**/*.vim')
  end
  return filter(split(pluginpaths. "\n". autoloadpaths, '\n'), 'v:val!=""')
endfunction
"}}}

function! s:_parse_exe(line) "{{{
  if a:line !~# '^\s*\%(sil\%[ent]!\?\s*\)\?exe\%[cute]\s'
    return a:line
  endif
  return substitute(substitute(a:line, '^\s*\%(sil\%[ent]!\?\s*\)\?exe\%[cute]\s\+', '', ''), '\(["'']\)\(.\{-}\)\1\s*', '\2 ', 'g')
endfunction
"}}}

"==================
"variables
function! s:_pick_var_default_val(val, var) "{{{
  let val = matchstr(a:val, 'get(\s*g:,\s*\(["'']\)'. substitute(a:var, 'g:', '', ''). '\1,\s*\zs.\+\ze)')
  if val!=''
    return val
  end
  let pat = 'exists(\s*\(["'']\)'. a:var. '\1\s*)\s*?\s*'
  let val = matchstr(a:val, pat. a:var. '\s*:\s*\zs.\+\ze\s*$')
  if val!=''
    return val
  end
  let val = matchstr(a:val, '!'. pat. '\zs.*\ze\s*:\s*'. a:var)
  return val=='' ? a:val : val
endfunction
"}}}
"commands
function! s:cmdattr(line) "{{{
  let attr = {'nargs': '', 'range': {}, 'is_bang': 0, 'is_register': 0, 'is_buflocal': 0, 'complete': ''}
  let attr.nargs = matchstr(a:line, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-nargs=\zs.')
  let attr.range.count = matchstr(a:line, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-count\s') ? 0 : matchstr(a:line, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-count=\zs\d\+')
  let attr.range.range = matchstr(a:line, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-range\s') ? 'current line' : matchstr(a:line, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-range=\zs\S\+')
  let attr.complete = matchstr(a:line, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-complete=\zs\S\+\ze\s')
  let attr.is_bang = a:line =~ 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-bang'
  let attr.is_register = a:line =~ 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-register'
  let attr.is_buflocal = a:line =~ 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-buffer'
  return attr
endfunction
"}}}
"keymappings
function! s:get_keymap_mode(mode, mapcmd) "{{{
  let is_remap = a:mapcmd !~# '[oicnvxs]n\|no'
  let modestrlist = matchlist(a:mapcmd, (is_remap ? '\(\l\?\)m\%[ap]\(!\?\)' : '\(\l\?\)n\%[oremap]\(!\?\)'))[1:2]
  let mode = s:_set_mode(a:mode, modestrlist)
  return [mode, is_remap]
endfunction
"}}}
function! s:_set_mode(mode, modestrlist) "{{{
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
  return a:mode
endfunction
"}}}
function! s:get_keymap_elements(options, line, mapcmd) "{{{
  let optionsstr = matchstr(a:line, '\%(\%(<buffer>\|<silent>\|<expr>\|<unique>\|<special>\|<script>\)\s*\)\+')
  let a:options.is_buflocal = optionsstr=~'<buffer>'
  let a:options.is_silent = optionsstr=~'<silent>'
  let a:options.is_unique = optionsstr=~'<unique>'
  let a:options.is_expr = optionsstr=~'<expr>'

  let lhs = matchstr(a:line, a:mapcmd. '\s\+'. optionsstr. '\zs\S\+')
  let rhs = matchstr(a:line, a:mapcmd. '\s\+'. optionsstr. escape(lhs, '~$.*\'). '\s\+\zs.\+')
  return [a:options, s:_format_keynotation(lhs), s:_format_keynotation(rhs)]
endfunction
"}}}
function! s:_format_keynotation(str) "{{{ <S-Up> <C-Down> etc.
  let str = substitute(substitute(a:str, '<\c\([CSM]-\)\?\(\a\{2}\)>', '<\U\1\2\E>', 'g'), '\c<\([CSM]-\)\?up>', '<\u\1Up>', 'g')
  return substitute(str, '\c<\([CSM]-\)\?\(\a\)\(\a\{2,}\)>', '<\u\1\u\2\L\3\E>', 'g')
endfunction
"}}}
"autocmds
function! s:au_join_escapedcomma_pat(patterns) "{{{
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
"merge_collector()
function! s:_marge_variablesvals(collectorvariables, var, elm) "{{{
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
      let a:modes[m] = get(a:modes, m, s:NEUTRAL_KEYMAPPINGMODES)
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


let s:Collector = {'variables': {}, 'commands': {}, 'globalkeymappings': {}, 'localkeymappings': {}, 'keymappings_catalog': {'rhs': [], 'is_buflocal': [], 'modes': [], 'lhs': []}, 'functions': {}, 'autocmds': [], 'unitesources': []}
function! s:newCollector(path, root) "{{{
  let obj = deepcopy(s:Collector)
  let obj.path = fnamemodify(a:path, ':p')
  let localpath = substitute(a:path, a:root. '/', '', '')
  let obj.autoload_prefix = localpath=~#'^autoload' ? fnamemodify(localpath, ':r:s?^autoload/??:gs?/?#?'). '#' : ''
  let [obj.lines, obj.len] = s:_remove_surplus_lines_and_join_continuation(readfile(a:path))
  return obj
endfunction
"}}}
function! s:_remove_surplus_lines_and_join_continuation(lines) "{{{
  let len = len(a:lines)
  let i = 0
  while i < len
    if a:lines[i] =~ '^\s*\\'
      let a:lines[i-1] .= substitute(remove(a:lines, i), '^\s*\\', '', '')
      let len -= 1
      continue
    elseif a:lines[i] =~ '^\s*$'
      unlet a:lines[i]
      let len -= 1
      continue
    elseif a:lines[i] !~ '^\s*"'
      let i += 1
      continue
    endif
    unlet a:lines[i]
    let len -= 1
    while get(a:lines, i, '') =~ '^\s*\\'
      unlet a:lines[i]
      let len -= 1
    endwhile
  endwhile
  return [a:lines, len]
endfunction
"}}}
function! s:Collector.collect(kind) "{{{
  call call(get(self, '_add_'. a:kind. '_dynamicdef', self.nop), [], self)
  call call(get(self, '_init_'. a:kind, self.nop), [], self)
  let funcname = '_add_'. a:kind
  if !has_key(self, funcname)
    return
  endif
  let i = 0
  while i < self.len
    call self[funcname](self.lines[i])
    let i += 1
  endwhile
endfunction
"}}}
function! s:Collector._init_variables() "{{{
  let self._is_globalscope = 1
  let self._var_order = 0
endfunction
"}}}
function! s:Collector._init_commands() "{{{
  let self._cmd_order = 0
endfunction
"}}}
function! s:Collector._init_keymappings() "{{{
  let self._keymap_order = 0
endfunction
"}}}
function! s:Collector._init_autocmds() "{{{
  let self._aug_scope = 'END'
endfunction
"}}}
function! s:Collector._add_variables(line) "{{{
  let self._is_globalscope = a:line=~#'^\s*endf\%[unction]\>' ? 1 : a:line=~#'^\s*fu\%[nction]!\?\_s' ? 0 : self._is_globalscope
  if self.autoload_prefix!=''
    let alvars = matchlist(a:line, 'let\s\+\%(g:\)\?\('. self.autoload_prefix. '\S\+\)\s*=\(.*\)')
    if alvars!=[]
      call self._register_variables(alvars[1])
      call self._register_value(alvars[2], alvars[1])
    end
  end
  let pat = self._is_globalscope ? 'g:[0-9A-Za-z_#]\+\|let\s\+\zs\w[^:][0-9A-Za-z_#]*' : 'g:[0-9A-Za-z_#]\+'
  let i = 1
  let var = matchstr(a:line, pat, 0, i)
  while var!=''
    if var !~# 'g:loaded_'
      call self._register_variables(var)
      let val = matchstr(a:line, 'let\s\+'. var. '\s*\zs=.*')
      if val!=''
        call self._register_value(val, var)
      end
    endif
    let i+=1
    let var = matchstr(a:line, pat, 0, i)
  endwhile
endfunction
"}}}
function! s:Collector._add_commands(line) "{{{
  if a:line !~# '^\s*com\%[mand]!\?\>'
    return
  endif
  let cmdname = matchstr(a:line, 'com\%[mand]!\?\s\+\%(-\S\+\s\+\)*\zs\u\S*\ze')
  let self._cmd_order += has_key(self.commands, cmdname) ? 0 : 1
  let self.commands[cmdname] = extend(s:cmdattr(a:line), {'order': self._cmd_order})
endfunction
"}}}
function! s:Collector._add_keymappings(line) "{{{
  let mapcmd = matchstr(a:line, '^\s*\%(sil\%[ent!]\s\+\)\?\zs\%([nvxoic]m\%[ap]\|s\?map!\?\|[oic]\?no\%[remap]!\?\|[nvx]n\%[oremap]\|snor\%[emap]\)\ze\s')
  if mapcmd == ''
    return
  endif
  let [mode, is_remap] = s:get_keymap_mode({'n': 0, 'i': 0, 'c': 0, 'o': 0, 'x': 0, 's': 0}, mapcmd)
  let [options, lhs, rhs] = s:get_keymap_elements({'is_buflocal': 0, 'is_silent': 0, 'is_unique': 0, 'is_expr': 0}, a:line, mapcmd)
  if lhs == '' || rhs == ''
    return "mapcmd が誤爆したとき用
  endif
  let keymappings = options.is_buflocal ? self.localkeymappings : self.globalkeymappings
  if !has_key(keymappings, lhs)
    let self._keymap_order += 1
    let keymappings[lhs] = {'common': {'is_defaultmapping': 0, 'is_local': options.is_buflocal, 'order': self._keymap_order}}
  end
  for m in ['n', 'i', 'c', 'o', 'x', 's']
    if !mode[m]
      continue
    endif
    let keymappings[lhs][m] = has_key(keymappings[lhs], m) ? keymappings[lhs][m]
      \ : {'rhs': [], 'defaultmappings': [], 'localdefaultmappings': []}
    call add(keymappings[lhs][m].rhs, rhs)
  endfor
  call add(self.keymappings_catalog.rhs, rhs)
  call add(self.keymappings_catalog.is_buflocal, options.is_buflocal)
  call add(self.keymappings_catalog.modes, keys(filter(mode, 'v:val==1')))
  call add(self.keymappings_catalog.lhs, lhs)
endfunction
"}}}
function! s:Collector._add_keymappings_dynamicdef() "{{{
  let idx = match(self.lines, 'textobj#user#plugin')
  if idx==-1
    return
  endif
endfunction
"}}}
function! s:Collector._add_functions(line) "{{{
  let func = matchlist(a:line, '^\s*fu\%[nction]!\?\s\+\(.\+\)(\(.*\))')
  if func == []
    return
  endif
  let [funcname, param] = func[1:2]
  let self.functions[funcname] = {'param': substitute(substitute(param, '\w\+\|\.\.\.', '{\0}', 'g'), '_', '-', 'g')}
  let self.functions[funcname].is_global = funcname =~ '^\u\|^[^s]:'. (self.autoload_prefix == '' ? '' : '\|'. self.autoload_prefix)
  let self.functions[funcname].is_dict = funcname =~ '\.\|\['
endfunction
"}}}
function! s:Collector._add_autocmds(line) "{{{
  let self._aug_scope = a:line!~#'\<aug\%[roup]\>' ? self._aug_scope :
    \ substitute(matchstr(a:line, 'aug\%[roup]\s\+\zs\w\+'), '^\cend$', 'END', '')
  if a:line !~# '\<au\%[tocmd]\s'
    return
  endif
  let _ = matchlist(a:line, s:AUTOCMDS_PAT)
  if _==[]
    return
  end
  call add(self.autocmds, {'group': _[1]=='' ? self._aug_scope : _[1], 'events': split(_[2], ','),
    \ 'patterns': s:au_join_escapedcomma_pat(split(_[3], ',')), 'cmd': _[4]})
endfunction
"}}}
function! s:Collector._add_unitesources(line) "{{{
  let sourcename = matchstr(a:line, 'fu\%[nction]!\?\s\+unite#sources#\zs\w\+\ze#define()')
  if sourcename!=''
    call add(self.unitesources, sourcename)
  endif
endfunction
"}}}
function! s:Collector._add_unitesources_dynamicdef() "{{{
  let idxes = []
  let idx = match(self.lines, 'unite#define_source')
  while idx!=-1
    call add(idxes, idx)
    let idx = match(self.lines, 'unite#define_source', idx+1)
  endwhile
  if idxes==[]
    return
  endif
  for idx in idxes
    let sourcevar = matchstr(self.lines[idx], 'unite#define_source(\s*\zs\S\+\ze\s*)')
    let sourcename = matchstr(self.lines, '^\s*let\s\+'. sourcevar. '\%(.name\|\[["'']name["'']\]\)\s*=')
    if sourcename==''
      let idx = match(self.lines, '^\s*let\s\+'. sourcevar. '\s*=')
      let sourcename = matchstr(self.lines[idx], '^\s*let\s\+'. sourcevar. '\s*=\s*{.*["'']name["'']\s*:\s*["'']\zs[a-z0-9_/]')
    else
      let sourcename = matchstr(sourcename, '^\s*let\s\+'. sourcevar. '\%(.name\|\[["'']name["'']\]\)\s*=\s*["'']\zs[a-z0-9_/]\+')
    endif
    if sourcename==''
      echohl WarningMsg| echom 'unite-source-nameの取得に失敗しました: '. self.path | echohl NONE
    else
      call add(self.unitesources, sourcename)
    endif
  endfor
endfunction
"}}}
function! s:Collector._register_variables(var) "{{{
  if has_key(self.variables, a:var)
    return
  end
  let self._var_order += 1
  let self.variables[a:var] = {'vals': [], 'is_dict': 0, 'order': self._var_order}
endfunction
"}}}
function! s:Collector._register_value(val, var) "{{{
  let val = s:_pick_var_default_val(a:val, a:var)
  let varlist = self.variables[a:var]
  let varlist.is_dict = val=~'^{' ? 1 : 0
  if index(varlist.vals, val) == -1
    call add(varlist.vals, val)
  endif
endfunction
"}}}
function! s:Collector.nop() "{{{
endfunction
"}}}

let s:ElementHolder = {}
function! s:newElementHolder(root, name, paths) "{{{
  let obj = copy(s:ElementHolder)
  let obj.root = a:root
  let obj.name = a:name
  let obj.paths = a:paths
  let obj.keymappings_catalog = {'rhs': [], 'is_buflocal': [], 'modes': [], 'lhs': []}
  let obj.elements = {'variables': {}, 'commands': {}, 'globalkeymappings': {}, 'localkeymappings': {}, 'functions': {}, 'autocmds': [], 'unitesources': []}
  return obj
endfunction
"}}}
function! s:ElementHolder.merge_collector(collector) "{{{
  call map(self.elements.variables, 's:_marge_variablesvals(a:collector.variables, v:key, v:val)')
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
function! s:ElementHolder.set_default_keymappings() "{{{
  for lhs in keys(self.elements.globalkeymappings) + keys(self.elements.localkeymappings)
    if lhs =~? '^<Plug>'
      call s:_find_pluginmapping_from_rhss(lhs, self.elements.globalkeymappings, self.elements.localkeymappings, self.keymappings_catalog)
    endif
  endfor
  unlet self.keymappings_catalog
endfunction
"}}}
function! s:ElementHolder.get_collections() "{{{
  unlet self.merge_collector
  unlet self.set_default_keymappings
  unlet self.get_collections
  return self
endfunction
"}}}


"========================================================
"Main:
function! __vimhelpgenerator#lim#alzplugin#analyze(...) "{{{
  let _ = s:init_args(a:000)
  if _=={}
    return {}
  end
  let paths = s:get_paths(_.root, _.name, index(_.collecttargets, 'unitesources')!=-1)
  let elementholder = s:newElementHolder(_.root, _.name, paths)
  for path in paths
    let collector = s:newCollector(path, _.root)
    for target in _.collecttargets
      call collector.collect(target)
    endfor
    call elementholder.merge_collector(collector)
  endfor
  call elementholder.set_default_keymappings()
  return elementholder.get_collections()
endfunction
"}}}

"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
