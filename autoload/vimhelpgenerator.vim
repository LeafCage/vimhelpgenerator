if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
"=============================================================================
let g:vimhelpgenerator_version = get(g:, 'vimhelpgenerator_version', 'Version :')
let g:vimhelpgenerator_author = get(g:, 'vimhelpgenerator_author', 'Author  :')
let g:vimhelpgenerator_license = get(g:, 'vimhelpgenerator_license', 'vimhelpgenerator/MIT')
let g:vimhelpgenerator_modeline = get(g:, 'vimhelpgenerator_modeline', 'vim:tw=78:ts=8:ft=help:norl:noet:fen:fdl=0:')
let g:vimhelpgenerator_defaultlanguage = get(g:, 'vimhelpgenerator_defaultlanguage', 'ja')
let g:vimhelpgenerator_defaultoverrider = get(g:, 'vimhelpgenerator_defaultoverrider', 'default')
let s:vimhelpgenerator_contents = {'contents': 1, 'introduction': 1, 'usage': 1,
  \ 'interface': 1, 'variables': 1, 'commands': 1, 'key-mappings': 1, 'functions': 1,
  \ 'setting': 0, 'todo': 1, 'changelog': 1,}
let g:vimhelpgenerator_contents = get(g:, 'vimhelpgenerator_contents', {})
call extend(g:vimhelpgenerator_contents, s:vimhelpgenerator_contents, 'keep')
unlet s:vimhelpgenerator_contents

"=============================================================================
let s:manager = {}
function! s:new_manager(path)
  let manager = {'name': '', 'rootpath': '', 'is_failinit': 0, 'keymappings_catalog': {'rhs': [], 'is_buflocal': [], 'modes': [], 'lhs': []}, 'elements': {'variables': {}, 'commands': {}, 'globalkeymappings': {}, 'localkeymappings': {}, 'functions': {}}}
  call extend(manager, s:manager, 'keep')
  call manager._set_rootpath_and_name(a:path)
  return manager
endfunction
function! s:manager._set_rootpath_and_name(path) "{{{
  for dir in ['after', 'autoload', 'plugin', 'syntax', 'ftplugin', 'ftdetect']
    let findpath = finddir(dir, (filereadable(a:path) ? fnamemodify(a:path, ':h') : a:path). ';**/vimfiles')
    if findpath == ''
      continue
    endif
    let self.rootpath = fnamemodify(findpath, ':p:h:h')
    let self.name = fnamemodify(self.rootpath, ':t:r')
    if self.name == 'vimfiles'
      continue
    endif
    for expr in ['/plugin/*.vim', '/syntax/*.vim', '/autoload/*.vim', '/autoload/*/']
      let file = glob(self.rootpath. expr)
      if file == '' || file =~ "\n"
        continue
      endif
      let self.name = fnamemodify(file, expr=='/autoload/*/' ? ':h:t' : ':t:r')
      return
    endfor
    return
  endfor
  let self.is_failinit = 1
endfunction
"}}}
function! s:manager.filepaths() "{{{
  let pluginpaths = globpath(self.rootpath. '/plugin', '**/*.vim')
  let autoloadpaths = globpath(self.rootpath. '/autoload', self.name. '/**/*.vim')
  let autoloadfile = globpath(self.rootpath. '/autoload', self.name. '.vim')
  let self.filepaths = filter(split(pluginpaths. "\n". autoloadpaths. "\n". autoloadfile, '\n'), 'v:val!=""')
  return self.filepaths
endfunction
"}}}
function! s:manager.add(collector) "{{{
  call map(self.elements.variables, 's:_combine_variablesvals(a:collector.variables, v:key, v:val)')
  call extend(self.elements.variables, a:collector.variables, 'keep')
  try
    call extend(self.elements.commands, a:collector.commands, 'error')
  catch /E737/
    echoerr 'VimHelpGenerator: 同名のコマンドが複数定義されています。'. v:exception
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
endfunction
"}}}
function! s:manager.set_default_keymappings() "{{{
  for lhs in keys(self.elements.globalkeymappings) + keys(self.elements.localkeymappings)
    if lhs =~? '^<Plug>'
      call s:_find_pluginmapping_from_rhss(lhs, self.elements.globalkeymappings, self.elements.localkeymappings, self.keymappings_catalog)
    endif
  endfor
  unlet self.keymappings_catalog
endfunction
"}}}
"==================
let s:collector = {}
function! s:new_collector(path, rootpath)
  let collector = {'variables': {}, 'commands': {}, 'globalkeymappings': {}, 'localkeymappings': {}, 'keymappings_catalog': {'rhs': [], 'is_buflocal': [], 'modes': [], 'lhs': []}, 'functions': {},}
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
  let funcname = '_add_'. a:kind
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
  let autoloadvar = self.autoload_prefix=='' ? '' : matchstr(linestr, 'let\s\+\zs'. self.autoload_prefix. '\S\+\ze\+\s*=')
  if autoloadvar != ''
    call self.__add_variables(autoloadvar, a:idx)
  endif

  let i = 1
  while 1
    let var = matchstr(linestr, 'g:\w\+', 0, i)
    if var == '' || var =~# 'g:loaded_'
      return
    endif
    call self.__add_variables(var, a:idx)
    let i += 1
  endwhile
endfunction
"}}}
function! s:collector._add_commands(idx) "{{{
  let linestr = self.lines[a:idx]
  if linestr !~ '^\s*com\%[mand]!\?\s'
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
"==================
let s:generator = {}
function! s:new_generator(overrider_name, manager)
  let generator = {'name': a:manager.name, 'rootpath': a:manager.rootpath, 'variables': {}, 'commands': {}, 'globalkeymappings': {}, 'localkeymappings': {}, 'functions': {}, 'words': (g:vimhelpgenerator_defaultlanguage==?'ja' ? s:_ja_words() : s:_en_words()), 'lang': g:vimhelpgenerator_defaultlanguage}
  call extend(generator, a:manager.elements)
  call extend(generator, s:generator, 'keep')
  try
    call extend(generator, vimhelpgenerator#overrider#{a:overrider_name}#generator())
  catch /E117/
    echohl WarningMsg
    echo 'VimHelpGenerator: invalid overrider name > '. a:overrider_name
    echohl NONE
  endtry
  return generator
endfunction
function! s:generator.make_gitignore() "{{{
  let gitignore_lines = ['/doc/tags*']
  let gitignore_file = self.rootpath. '/.gitignore'
  if !filereadable(gitignore_file)
    call writefile(gitignore_lines, gitignore_file)
  endif
endfunction
"}}}
function! s:generator.make_readme() "{{{
  let lines = ['# '. self.name. '.vim', '', '## Docs', 'see `:h '. self.name. '`']
  let readme_file = self.rootpath. '/README.md'
  if !filereadable(readme_file)
    call writefile(lines, readme_file)
  endif
endfunction
"}}}
function! s:generator.make_help(lines) "{{{
  let helpdir = self.rootpath. '/doc'
  let helppath = helpdir. '/'. self.name. (self.lang ==? 'ja' ? '.jax': '.txt')
  if filereadable(helppath)
    let helppath .= '1'
  endif
  if !isdirectory(helpdir)
    call mkdir(helpdir, 'p')
  endif
  call writefile(a:lines, helppath)
  return helppath
endfunction
"}}}
function! s:generator.build_helplines() "{{{
  let self.sep_l = repeat('=', 78)
  let self.sep_s = repeat('-', 78)
  let lines = []

  call extend(lines, ['*'. self.name. ".txt*\t". self.words.summary, ''])
  if g:vimhelpgenerator_version != ''
    call add(lines, g:vimhelpgenerator_version)
  endif
  if g:vimhelpgenerator_author != ''
    call add(lines, g:vimhelpgenerator_author)
  endif
  let license_file = findfile(g:vimhelpgenerator_license, &rtp)
  if filereadable(license_file)
    call extend(lines, readfile(license_file))
  else
    call add(lines, '')
  endif

  let contents = self._contentskeys()
  for c in map(contents, 'substitute(v:val, "key-mappings", "keymappings", "")')
    call extend(lines, self['_'. c]())
  endfor
  call extend(lines, [self.sep_l, g:vimhelpgenerator_modeline])
  return lines
endfunction
"}}}
function! s:generator._contents() "{{{
  let lines = ['', self.sep_l, self._caption(self.words.contents, 'contents'), '',]
  let contents = self._contentskeys()
  for c in filter(contents, 'v:val!="contents"')
    call add(lines, self._contents_caption(self.words[c], c, (c=~'s$'?'  ':'')))
  endfor
  call extend(lines, ['', ''])
  return lines
endfunction
"}}}
function! s:generator._introduction() "{{{
  let lines = [self.sep_l, self._caption(self.words.introduction, 'introduction'), '', printf(self.words.introduction_preface, self.name), '', self.words['latest-version'], '', '']
  return lines
endfunction
"}}}
function! s:generator._usage() "{{{
  let lines = [self.sep_l, self._caption(self.words.usage, 'usage'), '', '', '']
  return lines
endfunction
"}}}
function! s:generator._interface() "{{{
  let lines = [self.sep_l, self._caption(self.words.interface, 'interface'), '']
  return lines
endfunction
"}}}
function! s:generator._variables() "{{{
  let lines = [self.sep_s, self._caption(self.words.variables, 'variables'), '']
  for var in map(sort(items(self.variables), 's:_sort_variables'), 'v:val[0]')
    call extend(lines, self._interface_caption(var, var))
    if self.variables[var].vals != []
      for val in self.variables[var].vals
        if val =~ "\n"
          call add(lines, "\t". self.words['default-value']. ' >')
          call extend(lines, split("\t". val, '\n'))
          call add(lines, '<')
        else
          call add(lines, "\t". self.words['default-value']. substitute(val, '''', '"', 'g'))
        endif
      endfor
    endif
    call extend(lines, ['', ''])
  endfor
  return lines
endfunction
"}}}
function! s:generator._commands() "{{{
  let lines = [self.sep_s, self._caption(self.words.commands, 'commands'), '']
  let globalcmds = filter(copy(self.commands), '!v:val.is_buflocal')
  call self.__append_commands_lines(lines, globalcmds)
  let buflocalcmds = filter(copy(self.commands), 'v:val.is_buflocal')
  call self.__append_commands_lines(lines, buflocalcmds)
  return lines
endfunction
"}}}
function! s:generator._keymappings() "{{{
  let sep_ss = repeat('-', 39)
  let lines = [self.sep_s, self._caption(self.words['key-mappings'], 'key-mappings'), '']
  let [GLOBAL, LOCAL] = [0, 1]
  call self.__append_keymapping_lines(lines, self.globalkeymappings, GLOBAL)
  call self.__append_keymapping_lines(lines, self.localkeymappings, LOCAL)
  let globaldefaultkeymappings = filter(copy(self.globalkeymappings), 'v:val.common.is_defaultmapping')
  let localdefaultkeymappings = filter(copy(self.localkeymappings), 'v:val.common.is_defaultmapping')
  if globaldefaultkeymappings != {} || localdefaultkeymappings != {}
    call extend(lines, [self._caption('', 'default-key-mappings'), ''])
    call self.__append_defaultkeymappinglist_lines(lines, globaldefaultkeymappings, GLOBAL)
    call self.__append_defaultkeymappinglist_lines(lines, localdefaultkeymappings, LOCAL)
  endif
  return lines
endfunction
"}}}
function! s:generator._functions() "{{{
  let lines = [self.sep_s, self._caption(self.words.functions, 'functions'), '']
  let globalfuncs = keys(filter(copy(self.functions), 'v:val.is_global'))
  for func in sort(globalfuncs)
    call extend(lines, self._interface_caption(printf('%s(%s)', func, self.functions[func].param), func))
    call extend(lines, ['', ''])
  endfor
  return lines
endfunction
"}}}
function! s:generator._setting() "{{{
  let lines = [self.sep_l, self._caption(self.words.setting, 'setting'), '']
  return lines
endfunction
"}}}
function! s:generator._todo() "{{{
  let lines = [self.sep_l, self._caption(self.words.todo, 'todo'), '', '', '']
  return lines
endfunction
"}}}
function! s:generator._changelog() "{{{
  let lines = [self.sep_l, self._caption(self.words.changelog, 'changelog'), '', '']
  return lines
endfunction
"}}}

"========================================================
"Main
function! vimhelpgenerator#generate(...)
  let [s:_var_order, s:_command_order, s:_keymapping_order] = [0, 0, 0]
  let path = fnamemodify(expand(get(a:, 2, '%')), ':p')
  let manager = s:new_manager(path)
  if manager.is_failinit
    echohl WarningMsg |echo 'VimHelpGenerator: failed.' |echohl NONE
    return {'mes': 'VimHelpGenerator: failed.'}
  endif
  if s:_confirm(manager)
    return {'mes': 'canceled'}
  endif
  redraw

  for scriptpath in manager.filepaths()
    let collector = s:new_collector(scriptpath, manager.rootpath)
    call collector.collect('variables')
    call collector.collect('commands')
    call collector.collect('keymappings')
    call collector.collect('functions')
    call manager.add(collector)
  endfor
  unlet! s:_var_order s:_command_order s:_keymapping_order
  call manager.set_default_keymappings()
  let overrider_name = get(a:, 1, '""')
  let overrider_name = overrider_name=~'^[''"]\+$' ? g:vimhelpgenerator_defaultoverrider : overrider_name
  let generator = s:new_generator(overrider_name, manager)
  call generator.make_gitignore()
  call generator.make_readme()
  let lines = generator.build_helplines()
  let path = generator.make_help(lines)
  silent exe 'edit '. path
  return manager
endfunction



"======================================
"main
function! s:_confirm(manager) "{{{
  let input = input(printf('%s  "%s"  [e]xecute/[r]ename/[q]uit: ', a:manager.rootpath, a:manager.name), '', )
  if input == 'r'
    let a:manager.name = input('input plugin-name: ', a:manager.name)
    if a:manager.name == ''
      return 1
    endif
    let input = 'e'
  endif
  if input != 'e'
    return 1
  endif
endfunction
"}}}
"==================
"manager
"add()
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
  let i = 1
  while 1
    let idx = match(a:keymappings_catalog.rhs, a:pluginmapping, 0, i)
    if idx == -1
      return
    endif
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
    let i += 1
  endwhile
endfunction
"}}}
function! s:_add_without_duplicate(list, expr) "{{{
  if index(a:list, a:expr) == -1
    call add(a:list, a:expr)
  endif
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
  return matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*\zs\u\S*\ze')
endfunction
"}}}
function! s:_commandattr(linestr) "{{{
  let attr = {'nargs': '', 'range': {}, 'is_bang': 0, 'is_register': 0, 'is_buflocal': 0}
  let attr.nargs = matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-nargs=\zs.')
  let attr.range.count = matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-count\s') ? 0 : matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-count=\zs\d\+')
  let attr.range.range = matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-range\s') ? 'current line' : matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-range=\zs\S\+')
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
function! s:_neutral_keymappingmodes() "{{{
  return {'rhs': [], 'defaultmappings': [], 'localdefaultmappings': []}
endfunction
"}}}
"==================
"generator
function! s:_ja_words() "{{{
  return {'summary': '要約', 'contents': '目次', 'introduction': '概要', 'introduction_preface': '*%s* は',
    \ 'latest-version': '最新版:', 'usage': '使い方', 'interface': 'インターフェイス',
    \ 'variables': '変数', 'default-value': '既定値: ', 'commands': 'コマンド', 'buffer-local-command': 'バッファローカルなコマンド',
    \ 'lines': '行', 'default': '既定:', 'whole-file': 'ファイル全体', 'key-mappings': 'キーマッピング', 'enablemodes': '有効モード',
    \ 'buffer-local-mapping': 'バッファローカルなマッピング', 'defaultmappings_global': 'デフォルトマッピング(グローバル)', 'defaultmappings_local': 'デフォルトマッピング(バッファローカル)', 'defaultmappings': 'デフォルトマッピング', 'localdefaultmappings': 'ローカルデフォルトマッピング',
    \ 'modeshortname': {'n': 'ノーマル', 'x': 'ビジュアル', 's': 'セレクト', 'o': 'オペレータ', 'i': 'インサート', 'c': 'コマンドライン'},
    \ 'modename': {'n': 'ノーマルモード', 'x': 'ビジュアルモード', 's': 'セレクトモード', 'o': 'オペレータモード', 'i': 'インサートモード', 'c': 'コマンドライン'},
    \ 'functions': '関数', 'setting': '設定', 'todo': 'TODO', 'changelog': '更新履歴', }
endfunction
"}}}
function! s:_en_words() "{{{
  return {'summary': 'a summary', 'contents': 'CONTENTS', 'introduction': 'INTRODUCTION', 'introduction_preface': '*%s* is a Vim plugin ',
    \ 'latest-version': 'Latest version:', 'usage': 'USAGE', 'interface': 'INTERFACE',
    \ 'variables': 'VARIABLES', 'default-value': 'default value: ', 'commands': 'COMMANDS', 'buffer-local-command': 'buffer local command',
    \ 'lines': 'lines', 'default': 'default:', 'whole-file': 'whole file', 'key-mappings': 'KEY-MAPPINGS', 'enablemodes': '有効モード',
    \ 'buffer-local-mapping': 'buffer local mapping', 'defaultmappings_global': 'default mappings (global)', 'defaultmappings_local': 'default mapping (buffer local)', 'defaultmappings': 'default mappings', 'localdefaultmappings': 'local default mappings',
    \ 'modeshortname': {'n': 'normal', 'x': 'visual', 's': 'select', 'o': 'operator', 'i': 'insert', 'c': 'commandline'},
    \ 'modename': {'n': 'normal mode', 'x': 'visual mode', 's': 'select mode', 'o': 'operator mode', 'i': 'insert mode', 'c': 'commandline'},
    \ 'functions': 'FUNCTIONS', 'setting': 'SETTING', 'todo': 'TODO', 'changelog': 'CHANGELOG', }
endfunction
"}}}
function! s:generator._caption(title, tag) dict "{{{
  let tabnum = 6 - (strdisplaywidth(a:title) / 8)
  return printf('%s%s*%s-%s*', a:title, repeat("\t", tabnum), self.name, a:tag)
endfunction
"}}}
function! s:generator._interface_caption(title, tag) "{{{
  let titlelen = strdisplaywidth(a:title)
  let taglen = strdisplaywidth(a:tag)
  if taglen <= 28 && titlelen <= 40
    let tabnum = 6 - (titlelen / 8)
    return [printf('%s%s*%s*', a:title, repeat("\t", tabnum), a:tag)]
  elseif taglen > 28 && titlelen < 39
    let tabnum = 5 - (titlelen / 8)
    return [printf('%s%s*%s*', a:title, repeat("\t", tabnum), a:tag)]
  else
    let tabnum = (78 - taglen - 2) / 8
    return [printf('%s*%s*', repeat("\t", tabnum > 6 ? 6 : tabnum), a:tag), a:title]
  endif
endfunction
"}}}
function! s:generator._contentskeys() "{{{
  return filter(sort(keys(filter(copy(g:vimhelpgenerator_contents), 'v:val!=0')), 's:_sort_contents'), 's:_remove_empty_interfaces(v:val, self)')
endfunction
"}}}
function! s:_sort_contents(content1, content2) "{{{
  let ret = g:vimhelpgenerator_contents[a:content1] - g:vimhelpgenerator_contents[a:content2]
  if ret != 0
    return ret
  endif
  return s:_expr_contents(a:content1) - s:_expr_contents(a:content2)
endfunction
"}}}
function! s:_expr_contents(c) "{{{
  return a:c=='contents' ? 1 : a:c=='introduction' ? 2 : a:c=='usage' ? 3 : a:c=='interface' ? 4 : a:c=='variables' ? 5 : a:c=='commands' ? 6 : a:c=='key-mappings' ? 7 : a:c=='functions' ? 8 : a:c=='todo' ? 9 : 10
endfunction
"}}}
function! s:_remove_empty_interfaces(content, this) "{{{
  if a:content=~'variables\|commands\|functions'
    return a:this[a:content] != {}
  endif
  if a:content=='key-mappings'
    return a:this.localkeymappings != {} || a:this.globalkeymappings != {}
  endif
  return 1
endfunction
"}}}
"make_help contents
function! s:generator._contents_caption(title, tag, ...) dict "{{{
  let padding = get(a:, 1, '')
  let tabnum = 4 - (strdisplaywidth(padding. a:title) / 8)
  return printf('%s%s%s%s|%s-%s|', padding, a:title, repeat("\t", tabnum), padding, self.name, a:tag)
endfunction
"}}}
"make_help variables
function! s:_sort_variables(item1, item2) "{{{
  return a:item1[1].order - a:item2[1].order
endfunction
"}}}
"make_help commands
function! s:generator.__append_commands_lines(lines, commands) "{{{
  for cmd in map(sort(items(a:commands), 's:_sort_commands'), 'v:val[0]')
    let [commandhelpstr, range_description] = self._build_commandhelpstr(cmd)
    call extend(a:lines, self._interface_caption(commandhelpstr, ':'. cmd))
    if self.commands[cmd].is_buflocal
      call add(a:lines, "\t". self.words['buffer-local-command'])
    endif
    if range_description != ''
      call add(a:lines, range_description)
    endif
    call extend(a:lines, ['', ''])
  endfor
endfunction
"}}}
function! s:_sort_commands(item1, item2) "{{{
  return a:item1[1].order - a:item2[1].order
endfunction
"}}}
function! s:generator._build_commandhelpstr(cmd) "{{{
  let commandhelpstr = ':'
  let range_description = ''
  let command = self.commands[a:cmd]
  if command.range.range != ''
    let commandhelpstr .= '[range]'
    let range_description = printf('[range] %s (%s%s)', self.words.lines, self.words.default, (command.range.range=='%' ? self.words['whole-file'] : command.range.range))
  endif
  if command.range.count != ''
    let commandhelpstr .= '[count]'
    let range_description = '[count] ('. self.words.default. command.range.count. ')'
  endif
  let commandhelpstr .= a:cmd
  let commandhelpstr .= command.is_bang ? '[!]' : ''
  let commandhelpstr .= command.is_register ? ' [x]' : ''
  if command.nargs == 1
    let commandhelpstr .= ' {}'
  elseif command.nargs == '?'
    let commandhelpstr .= ' [{}]'
  elseif command.nargs == '+'
    let commandhelpstr .= ' {} ...'
  elseif command.nargs == '*'
    let commandhelpstr .= ' [{} ...]'
  endif
  return [commandhelpstr, range_description]
endfunction
"}}}
"make_help keymappings
function! s:generator.__append_keymapping_lines(lines, keymappings, is_local) "{{{
  let baflocal_label = a:is_local ? ["\t". self.words['buffer-local-mapping']] : []
  let lhss = map(sort(filter(items(a:keymappings), 'v:val[0] =~? ''^<Plug>\|<Leader>\|<LocalLeader>'''), 's:_sort_lhs'), 'v:val[0]')
  for lhs in lhss
    call extend(a:lines, self._interface_caption(lhs, lhs))
    call extend(a:lines, baflocal_label)
    let validmodes = "\t". self.words.enablemodes. ":"
    let defaultmappings = []
    let localdefaultmappings = []
    let command = ''
    for m in sort(filter(keys(a:keymappings[lhs]), 'v:val!="common"'), 's:_sort_mode')
      let validmodes .= ' '. self.words.modeshortname[m]
      call add(defaultmappings, printf("\t\t%s:\t%s", self.words.modeshortname[m], join(a:keymappings[lhs][m].defaultmappings)))
      call add(localdefaultmappings, printf("\t\t%s:\t%s", self.words.modeshortname[m], join(a:keymappings[lhs][m].localdefaultmappings)))
      let command = matchstr(a:keymappings[lhs][m].rhs[0], '^:\%(<C-u>\)\?\zs\u\a\+\ze<CR>')
    endfor
    call add(a:lines, validmodes)
    if a:keymappings[lhs][m].defaultmappings != []
      call add(a:lines, "\t". self.words.defaultmappings_global. ":")
      call extend(a:lines, defaultmappings)
    endif
    if a:keymappings[lhs][m].localdefaultmappings != []
      call add(a:lines, "\t". self.words.defaultmappings_local. ":")
      call extend(a:lines, localdefaultmappings)
    endif
    if command != ''
      call add(a:lines, "\t|:". command. "|")
    endif
    call extend(a:lines, ['', ''])
  endfor
endfunction
"}}}
function! s:_sort_lhs(lhs1, lhs2) "{{{
  return s:_expr_modes(a:lhs2[1]) - s:_expr_modes(a:lhs1[1])
endfunction
"}}}
function! s:_expr_modes(modes) "{{{
  let expr = map(keys(a:modes), 'v:val=="n" ? 32 : v:val=="i" ? 16 : v:val=="x" ? 8 : v:val=="s" ? 4 : v:val=="o" ? 2 : v:val=="c" ? 1 : 0')
  return eval(join(expr, '+')) + 8000 - a:modes.common.order
endfunction
"}}}
function! s:_sort_mode(m1, m2) "{{{
  return s:_expr_mode(a:m2) - s:_expr_mode(a:m1)
endfunction
"}}}
function! s:_expr_mode(m) "{{{
  return a:m=='n' ? 32 : a:m=='i' ? 16 : a:m=='x' ? 8 : a:m=='s' ? 4 : a:m=='o' ? 2 : 1
endfunction
"}}}
function! s:generator.__append_defaultkeymappinglist_lines(lines, defaultkeymappings, is_local) "{{{
  if a:defaultkeymappings == {}
    return
  endif
  call add(a:lines, (a:is_local ? self.words.localdefaultmappings : self.words.defaultmappings))
  for m in ['n', 'i', 'x', 's', 'o', 'c']
    let lhss = sort(keys(filter(copy(a:defaultkeymappings), 'has_key(v:val, m)')))
    if lhss == []
      continue
    endif
    call extend(a:lines, [self.words.modename[m], "{lhs}\t\t{rhs}", "--------\t------------------------"])
    for lhs in lhss
      call add(a:lines, lhs. repeat("\t", (2 - strdisplaywidth(lhs) / 8)). join(a:defaultkeymappings[lhs][m].rhs))
    endfor
    call add(a:lines, '')
  endfor
  call add(a:lines, '')
endfunction
"}}}
"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
