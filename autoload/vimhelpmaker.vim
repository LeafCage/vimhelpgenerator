if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
"=============================================================================
let g:vimhelpmaker_author = get(g:, 'vimhelpmaker_author', 'Author:')
let g:vimhelpmaker_license = get(g:, 'vimhelpmaker_license', 'vimhelpmaker/mit_license')
let g:vimhelpmaker_modeline = get(g:, 'vimhelpmaker_modeline', 'vim:tw=78:ts=8:ft=help:norl:noet:fen:fdl=0:')
let s:vimhelpmaker_contents = {'contents': 1, 'introduction': 1, 'usage': 0,
  \ 'interface': 1, 'variables': 1, 'commands': 1, 'key-mappings': 1, 'functions': 1,
  \ 'todo': 0, 'changelog': 0,}
let g:vimhelpmaker_contents = get(g:, 'vimhelpmaker_contents', {})
call extend(g:vimhelpmaker_contents, s:vimhelpmaker_contents, 'keep')
let g:vimhelpmaker_helplang = get(g:, 'vimhelpmaker_helplang', 'ja')
let g:vimhelpmaker_readmefile = get(g:, 'vimhelpmaker_readmefile', 'md')

"=============================================================================
let s:maker = {}
function! s:new_maker(path)
  let maker = {'name': '', 'rootpath': '', 'is_failinit': 0, 'variables': {}, 'commands': {}, 'globalkeymappings': {}, 'localkeymappings': {}, 'keymappings_catalog': {'rhs': [], 'is_buflocal': [], 'modes': [], 'lhs': []}, 'functions': {}}
  call extend(maker, s:maker, 'keep')
  call maker._set_rootpath_and_name(a:path)
  return maker
endfunction
function! s:maker._set_rootpath_and_name(path) "{{{
  for dir in ['after', 'autoload', 'plugin', 'syntax', 'ftplugin', 'ftdetect']
    let findpath = finddir(dir, a:path. ';**/vimfiles')
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
function! s:maker.filepaths() "{{{
  let pluginpaths = globpath(self.rootpath. '/plugin', '**/*.vim')
  let autoloadpaths = globpath(self.rootpath. '/autoload', self.name. '/**/*.vim')
  let autoloadfile = globpath(self.rootpath. '/autoload', self.name. '.vim')
  let self.filepaths = filter(split(pluginpaths. "\n". autoloadpaths. "\n". autoloadfile, '\n'), 'v:val!=""')
  return self.filepaths
endfunction
"}}}
function! s:maker.add(gatherer) "{{{
  call map(self.variables, 's:_combine_variablesvals(a:gatherer.variables, v:key, v:val)')
  call extend(self.variables, a:gatherer.variables, 'keep')
  try
    call extend(self.commands, a:gatherer.commands, 'error')
  catch /E737/
    echoerr 'vimhelpmaker: 同名のコマンドが複数定義されています。'. v:exception
  endtry
  call map(self.localkeymappings, 's:_combine_keymapping(a:gatherer.localkeymappings, v:key, v:val)')
  call extend(self.localkeymappings, a:gatherer.localkeymappings, 'keep')
  call map(self.globalkeymappings, 's:_combine_keymappings(a:gatherer.globalkeymappings, v:key, v:val)')
  call extend(self.globalkeymappings, a:gatherer.globalkeymappings, 'keep')
  call extend(self.keymappings_catalog.rhs, a:gatherer.keymappings_catalog.rhs)
  call extend(self.keymappings_catalog.is_buflocal, a:gatherer.keymappings_catalog.is_buflocal)
  call extend(self.keymappings_catalog.modes, a:gatherer.keymappings_catalog.modes)
  call extend(self.keymappings_catalog.lhs, a:gatherer.keymappings_catalog.lhs)
  call extend(self.functions, a:gatherer.functions, 'keep')
endfunction
"}}}
function! s:maker.set_default_keymappings() "{{{
  for lhs in keys(self.globalkeymappings) + keys(self.localkeymappings)
    if lhs =~? '^<Plug>'
      call s:_find_pluginmapping_from_rhss(lhs, self.globalkeymappings, self.localkeymappings, self.keymappings_catalog)
    endif
  endfor
  unlet self.keymappings_catalog
endfunction
"}}}

function! s:maker.make_gitignore() "{{{
  let gitignore_lines = ['/doc/tags*']
  let gitignore_file = self.rootpath. '/.gitignore'
  if !filereadable(gitignore_file)
    call writefile(gitignore_lines, gitignore_file)
  endif
endfunction
"}}}
function! s:maker.make_help(lang) "{{{
  let self.lang = a:lang ==? 'ja' ? s:_ja_lang() : s:_en_lang()
  let self.sep_l = repeat('=', 78)
  let self.sep_s = repeat('-', 78)
  let self.caption = g:vimhelpmaker_modeline=~'noet\|noexpandtab' ? function('s:_caption_tab') : function('s:_caption_space')
  let self.interface = g:vimhelpmaker_modeline=~'noet\|noexpandtab' ? function('s:_interface_tab') : function('s:_interface_space')
  let lines = []

  let head = '*'. self.name. '.txt*'
  call extend(lines, [head, '', 'Version:'])
  if g:vimhelpmaker_author != ''
    call add(lines, g:vimhelpmaker_author)
  endif
  let license_file = findfile(g:vimhelpmaker_license, &rtp)
  if filereadable(license_file)
    call extend(lines, readfile(license_file))
  else
    call add(lines, '')
  endif

  if g:vimhelpmaker_contents.contents
    call extend(lines, self._contents())
  endif
  if g:vimhelpmaker_contents.introduction
    call extend(lines, self._introduction())
  endif
  if g:vimhelpmaker_contents.usage
    call extend(lines, self._usage())
  endif
  if g:vimhelpmaker_contents.interface
    call extend(lines, self._interface())
  endif
  if g:vimhelpmaker_contents.variables
    call extend(lines, self._variables())
  endif
  if g:vimhelpmaker_contents.commands
    call extend(lines, self._commands())
  endif
  if g:vimhelpmaker_contents['key-mappings']
    call extend(lines, self._keymappings())
  endif
  if g:vimhelpmaker_contents.functions
    call extend(lines, self._functions())
  endif
  if g:vimhelpmaker_contents.todo
    call extend(lines, self._todo())
  endif
  if g:vimhelpmaker_contents.changelog
    call extend(lines, self._changelog())
  endif
  call extend(lines, [self.sep_l, g:vimhelpmaker_modeline])

  let helpdir = self.rootpath. '/doc'
  let helppath = helpdir. '/'. self.name. (a:lang ==? 'ja' ? '.jax': '.txt')
  if filereadable(helppath)
    let helppath .= '1'
  endif
  if !isdirectory(helpdir)
    call mkdir(helpdir, 'p')
  endif
  call writefile(lines, helppath)
  return helppath
endfunction
"}}}
function! s:maker.make_readme() "{{{
endfunction
"}}}
"==================
let s:gatherer = {}
function! s:new_gatherer(path, rootpath)
  let gatherer = {'variables': {}, 'commands': {}, 'globalkeymappings': {}, 'localkeymappings': {}, 'keymappings_catalog': {'rhs': [], 'is_buflocal': [], 'modes': [], 'lhs': []}, 'functions': {},}
  let gatherer.path = fnamemodify(a:path, ':p')
  let gatherer.autoload_prefix = s:_autoload_prefix(a:path, a:rootpath)
  let gatherer.lines = filter(readfile(a:path), 'v:val !~ "^\\s*$"')
  call s:_exclude_commentline(gatherer.lines)
  call extend(gatherer, s:gatherer, 'keep')
  return gatherer
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
function! s:gatherer.gather(kind) "{{{
  let funcname = '_add_'. a:kind
  let i = 0
  let len = len(self.lines)
  while i < len
    call self[funcname](i)
    let i += 1
  endwhile
endfunction
"}}}
function! s:gatherer._add_variables(idx) "{{{
  let linestr = self.lines[a:idx]
  let autoloadvar = self.autoload_prefix=='' ? '' : matchstr(linestr, 'let\s\+\zs'. self.autoload_prefix. '\S\+\ze\+\s*=')
  if autoloadvar != ''
    let vallist = s:_add_var(self.variables, autoloadvar)
    let val = matchstr(linestr, 'let\s\+'. autoloadvar. '\s*=\zs.*')
    if val != ''
      let val = s:_join_val_line_continuation(val, self.lines, a:idx)
      call s:_add_val(vallist, val, autoloadvar)
    endif
  endif

  let i = 1
  while 1
    let var = matchstr(linestr, 'g:\w\+', 0, i)
    if var == '' || var =~# 'g:loaded_'
      return
    endif
    let vallist = s:_add_var(self.variables, var)
    let val = matchstr(linestr, 'let\s\+'. var. '\s*=\zs.*')
    if val != ''
      let val = s:_join_val_line_continuation(val, self.lines, a:idx)
      call s:_add_val(vallist, val, var)
    endif
    let i += 1
  endwhile
endfunction
"}}}
function! s:gatherer._add_commands(idx) "{{{
  let linestr = self.lines[a:idx]
  if linestr !~ '^\s*com\%[mand]!\?\s'
    return
  endif
  let linestr = s:_join_line_continuation(self.lines, a:idx)
  let linestr = s:_remove_nl_for_line_continuation(linestr)
  let commandname = s:_commandname(linestr)
  let self.commands[commandname] = s:_commandattr(linestr)
endfunction
"}}}
function! s:gatherer._add_keymappings(idx) "{{{
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
  let keymappings[lhs] = get(keymappings, lhs, {'common': {'is_defaultmapping': 0, 'is_local': options.is_buflocal}})
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
function! s:gatherer._add_functions(idx) "{{{
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

"========================================================
"Main
function! vimhelpmaker#make(...)
  let path = fnamemodify(expand(get(a:, 1, '%')), ':p')
  let maker = s:new_maker(path)
  if maker.is_failinit
    return 'vimhelpmaker: failed.'
  endif
  if !get(a:, 2, 0)
    if s:_confirm(maker)
      return ''
    endif
  endif

  for scriptpath in maker.filepaths()
    let gatherer = s:new_gatherer(scriptpath, maker.rootpath)
    call gatherer.gather('variables')
    call gatherer.gather('commands')
    call gatherer.gather('keymappings')
    call gatherer.gather('functions')
    call maker.add(gatherer)
  endfor
  call maker.set_default_keymappings()
  call maker.make_gitignore()

  let path = maker.make_help('ja')
  exe 'edit '. path
  return maker
  call maker.make_readme()
endfunction



"======================================
"main
function! s:_confirm(maker) "{{{
  let input = input(printf('%s  "%s"  [e]xecute/[r]ename/[q]uit: ', a:maker.rootpath, a:maker.name), '', )
  if input == 'r'
    let a:maker.name = input('input plugin-name: ', a:maker.name)
    if a:maker.name == ''
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
"maker
"add()
function! s:_combine_variablesvals(gatherervariables, var, elm) "{{{
  if has_key(a:gatherervariables, a:var)
    call extend(a:elm.vals, a:gatherervariables[a:var].vals)
  endif
  return a:elm
  "elm = {'vals': [], 'is_dict': 0}
endfunction
"}}}
function! s:_combine_keymappings(gathererkeymappings_lhs, lhs, elm) "{{{
  if has_key(a:gathererkeymappings_lhs, a:lhs)
    call extend(a:elm, a:gathererkeymappings_lhs[a:lhs])
  endif
  return a:elm
endfunction
"}}}
function! s:_combine_keymapping(gathererkeymappings, lhs, modes) "{{{
  if !has_key(a:gathererkeymappings, a:lhs)
    return a:modes
  endif
  for m in ['n', 'i', 'x', 's', 'o', 'c']
    if has_key(a:gathererkeymappings[a:lhs], m)
      let a:modes[m] = get(a:modes, m, s:_neutral_keymappingmodes())
      call extend(a:modes[m].rhs, a:gathererkeymappings[a:lhs][m].rhs)
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
"make_help misc
function! s:_ja_lang() "{{{
  return {'contents': '目次', 'introduction': '概要', 'introduction_preface': '*%s* は～するVimプラグインです。',
    \ 'requirements': '要件:', 'latest-version': '最新版:', 'usage': '使い方', 'interface': 'インターフェイス',
    \ 'variables': '変数', 'default': '既定: ', 'commands': 'コマンド', 'buffer-local-command': 'バッファローカルなコマンド',
    \ 'lines': '行', 'whole-file': 'ファイル全体', 'key-mappings': 'キーマッピング', 'enablemodes': '有効モード',
    \ 'buffer-local-mapping': 'バッファローカルなマッピング', 'defaultmappings_global': 'デフォルトマッピング(グローバル)', 'defaultmappings_local': 'デフォルトマッピング(バッファローカル)', 'defaultmappings': 'デフォルトマッピング', 'localdefaultmappings': 'ローカルデフォルトマッピング',
    \ 'modeshortname': {'n': 'ノーマル', 'x': 'ビジュアル', 's': 'セレクト', 'o': 'オペレータ', 'i': 'インサート', 'c': 'コマンドライン'},
    \ 'modename': {'n': 'ノーマルモード', 'x': 'ビジュアルモード', 's': 'セレクトモード', 'o': 'オペレータモード', 'i': 'インサートモード', 'c': 'コマンドライン'},
    \ 'functions': '関数', 'todo': 'TODO', 'changelog': '更新履歴', }
endfunction
"}}}
function! s:_en_lang() "{{{
  return {}
endfunction
"}}}
function! s:_caption_space(title, tag) dict "{{{
  let byte_display_diff = strlen(a:title) - strdisplaywidth(a:title)
  return printf('%-*s*%s-%s*', 48 + byte_display_diff, a:title, self.name, a:tag)
endfunction
"}}}
function! s:_caption_tab(title, tag) dict "{{{
  let tabnum = 6 - (strdisplaywidth(a:title) / 8)
  return printf('%s%s*%s-%s*', a:title, repeat("\t", tabnum), self.name, a:tag)
endfunction
"}}}
function! s:_interface_space(title, tag) "{{{
  if strdisplaywidth(a:tag) <= 28 && strdisplaywidth(a:title) <= 40
    let byte_display_diff = strlen(a:title) - strdisplaywidth(a:title)
    return [printf('%-*s*%s*', 48 + byte_display_diff, a:title, a:tag)]
  else
    if a:title == ''
      return [printf('%78s', '*'. a:tag. '*')]
    else
      return [printf('%78s', '*'. a:tag. '*'), a:title]
    endif
  endif
endfunction
"}}}
function! s:_interface_tab(title, tag) "{{{
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
"make_help main
function! s:maker._contents() "{{{
  let self.contents = g:vimhelpmaker_modeline=~'noet\|noexpandtab' ? function('s:_contents_tab') : function('s:_contents_space')
  let lines = ['', self.sep_l, self.caption(self.lang.contents, 'contents'), '',]
  if g:vimhelpmaker_contents.introduction
    call add(lines, self.contents(self.lang.introduction, 'introduction'))
  endif
  if g:vimhelpmaker_contents.usage
    call add(lines, self.contents(self.lang.usage, 'usage'))
  endif
  if g:vimhelpmaker_contents.interface
    call add(lines, self.contents(self.lang.interface, 'interface'))
  endif
  if g:vimhelpmaker_contents.variables
    call add(lines, self.contents(self.lang.variables, 'variables', '  '))
  endif
  if g:vimhelpmaker_contents.commands
    call add(lines, self.contents(self.lang.commands, 'commands', '  '))
  endif
  if g:vimhelpmaker_contents['key-mappings']
    call add(lines, self.contents(self.lang['key-mappings'], 'key-mappings', '  '))
  endif
  if g:vimhelpmaker_contents.functions
    call add(lines, self.contents(self.lang.functions, 'functions', '  '))
  endif
  if g:vimhelpmaker_contents.todo
    call add(lines, self.contents(self.lang.todo, 'todo'))
  endif
  if g:vimhelpmaker_contents.changelog
    call add(lines, self.contents(self.lang.changelog, 'changelog'))
  endif
  call extend(lines, ['', ''])
  unlet self.contents
  return lines
endfunction
"}}}
function! s:maker._introduction() "{{{
  let lines = [self.sep_l, self.caption(self.lang.introduction, 'introduction'), '', printf(self.lang.introduction_preface, self.name), '', self.lang.requirements, '- ', '', self.lang['latest-version'], '', '']
  return lines
endfunction
"}}}
function! s:maker._usage() "{{{
  let lines = [self.sep_l, self.caption(self.lang.usage, 'usage'), '', '']
  return lines
endfunction
"}}}
function! s:maker._interface() "{{{
  let lines = [self.sep_l, self.caption(self.lang.interface, 'interface'), '']
  return lines
endfunction
"}}}
function! s:maker._variables() "{{{
  let lines = [self.sep_s, self.caption(self.lang.variables, 'variables'), '']
  for var in sort(keys(self.variables))
    call extend(lines, self.interface(var, var))
    if self.variables[var].vals != []
      for val in self.variables[var].vals
        if val =~ "\n"
          call add(lines, "\t". self.lang.default. ' >')
          call extend(lines, split("\t". val, '\n'))
          call add(lines, '<')
        else
          call add(lines, "\t". self.lang.default. substitute(val, '''', '"', 'g'))
        endif
      endfor
    endif
    call extend(lines, ['', ''])
  endfor
  return lines
endfunction
"}}}
function! s:maker._commands() "{{{
  let lines = [self.sep_s, self.caption(self.lang.commands, 'commands'), '']
  let globalcmds = filter(copy(self.commands), '!v:val.is_buflocal')
  call self.__append_commands_lines(lines, globalcmds)
  let buflocalcmds = filter(copy(self.commands), 'v:val.is_buflocal')
  call self.__append_commands_lines(lines, buflocalcmds)
  return lines
endfunction
"}}}
function! s:maker._keymappings() "{{{
  let sep_ss = repeat('-', 39)
  let lines = [self.sep_s, self.caption(self.lang['key-mappings'], 'key-mappings'), '']
  let [GLOBAL, LOCAL] = [0, 1]
  call self.__append_keymapping_lines(lines, self.globalkeymappings, GLOBAL)
  call self.__append_keymapping_lines(lines, self.localkeymappings, LOCAL)
  let globaldefaultkeymappings = filter(copy(self.globalkeymappings), 'v:val.common.is_defaultmapping')
  let localdefaultkeymappings = filter(copy(self.localkeymappings), 'v:val.common.is_defaultmapping')
  if globaldefaultkeymappings != {} || localdefaultkeymappings != {}
    call extend(lines, [self.caption('', 'default-key-mappings'), ''])
    call self.__append_defaultkeymappinglist_lines(lines, globaldefaultkeymappings, GLOBAL)
    call self.__append_defaultkeymappinglist_lines(lines, localdefaultkeymappings, LOCAL)
  endif
  return lines
endfunction
"}}}
function! s:maker._functions() "{{{
  let lines = [self.sep_s, self.caption(self.lang.functions, 'functions'), '']
  let globalfuncs = keys(filter(copy(self.functions), 'v:val.is_global'))
  for func in sort(globalfuncs)
    call extend(lines, self.interface(printf('%s(%s)', func, self.functions[func].param), func))
    call extend(lines, ['', ''])
  endfor
  return lines
endfunction
"}}}
function! s:maker._todo() "{{{
  let lines = [self.sep_l, self.caption(self.lang.todo, 'todo'), '', '']
  return lines
endfunction
"}}}
function! s:maker._changelog() "{{{
  let lines = [self.sep_l, self.caption(self.lang.changelog, 'changelog'), '', '']
  return lines
endfunction
"}}}
"make_help contents
function! s:_contents_space(title, tag, ...) dict "{{{
  let padding = get(a:, 1, '')
  let byte_display_diff = strlen(a:title) - strdisplaywidth(a:title)
  return printf('%s%-*s%s|%s-%s|', padding, 32 + byte_display_diff, a:title, padding, self.name, a:tag)
endfunction
"}}}
function! s:_contents_tab(title, tag, ...) dict "{{{
  let padding = get(a:, 1, '')
  let tabnum = 4 - (strdisplaywidth(padding. a:title) / 8)
  return printf('%s%s%s%s|%s-%s|', padding, a:title, repeat("\t", tabnum), padding, self.name, a:tag)
endfunction
"}}}
"make_help commands
function! s:maker.__append_commands_lines(lines, commands) "{{{
  for cmd in sort(keys(a:commands))
    let [commandhelpstr, range_description] = self._build_commandhelpstr(cmd)
    call extend(a:lines, self.interface(commandhelpstr, ':'. cmd))
    if self.commands[cmd].is_buflocal
      call add(a:lines, "\t". self.lang['buffer-local-command'])
    endif
    if range_description != ''
      call add(a:lines, range_description)
    endif
    call extend(a:lines, ['', ''])
  endfor
endfunction
"}}}
function! s:maker._build_commandhelpstr(cmd) "{{{
  let commandhelpstr = ':'
  let range_description = ''
  let command = self.commands[a:cmd]
  if command.range.range != ''
    let commandhelpstr .= '[range]'
    let range_description = printf('[range] %s (%s%s)', self.lang.lines, self.lang.default, (command.range.range=='%' ? self.lang['whole-file'] : command.range.range))
  endif
  if command.range.count != ''
    let commandhelpstr .= '[count]'
    let range_description = '[count] ('. self.lang.default. command.range.count. ')'
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
function! s:maker.__append_keymapping_lines(lines, keymappings, is_local) "{{{
  let baflocal_label = a:is_local ? ["\t". self.lang['buffer-local-mapping']] : []
  let s:keymappings = a:is_local ? self.localkeymappings : self.globalkeymappings
  let lhss = sort(filter(keys(a:keymappings), 'v:val =~? ''^<Plug>\|<Leader>\|<LocalLeader>'''), 's:_sort_lhs')
  unlet s:keymappings
  for lhs in lhss
    call extend(a:lines, self.interface(lhs, lhs))
    call extend(a:lines, baflocal_label)
    let validmodes = "\t". self.lang.enablemodes. ":"
    let defaultmappings = []
    let localdefaultmappings = []
    let command = ''
    for m in sort(filter(keys(a:keymappings[lhs]), 'v:val!="common"'), 's:_sort_mode')
      let validmodes .= ' '. self.lang.modeshortname[m]
      call add(defaultmappings, printf("\t\t%s:\t%s", self.lang.modeshortname[m], join(a:keymappings[lhs][m].defaultmappings)))
      call add(localdefaultmappings, printf("\t\t%s:\t%s", self.lang.modeshortname[m], join(a:keymappings[lhs][m].localdefaultmappings)))
      let command = matchstr(a:keymappings[lhs][m].rhs[0], '^:\%(<C-u>\)\?\zs\u\a\+\ze<CR>')
    endfor
    call add(a:lines, validmodes)
    if a:keymappings[lhs][m].defaultmappings != []
      call add(a:lines, "\t". self.lang.defaultmappings_global. ":")
      call extend(a:lines, defaultmappings)
    endif
    if a:keymappings[lhs][m].localdefaultmappings != []
      call add(a:lines, "\t". self.lang.defaultmappings_local. ":")
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
  return s:_expr_modes(keys(s:keymappings[a:lhs2])) - s:_expr_modes(keys(s:keymappings[a:lhs1]))
endfunction
"}}}
function! s:_expr_modes(modes) "{{{
  let expr = map(a:modes, 'v:val=="n" ? 32 : v:val=="i" ? 16 : v:val=="x" ? 8 : v:val=="s" ? 4 : v:val=="o" ? 2 : 1')
  return eval(join(expr, '+'))
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
function! s:maker.__append_defaultkeymappinglist_lines(lines, defaultkeymappings, is_local) "{{{
  if a:defaultkeymappings == {}
    return
  endif
  call add(a:lines, (a:is_local ? self.lang.localdefaultmappings : self.lang.defaultmappings))
  for m in ['n', 'i', 'x', 's', 'o', 'c']
    let lhss = sort(keys(filter(copy(a:defaultkeymappings), 'has_key(v:val, m)')))
    if lhss == []
      continue
    endif
    call extend(a:lines, [self.lang.modename[m], "{lhs}\t\t{rhs}", "--------\t------------------------"])
    for lhs in lhss
      call add(a:lines, lhs. repeat("\t", (2 - strdisplaywidth(lhs) / 8)). join(a:defaultkeymappings[lhs][m].rhs))
    endfor
    call add(a:lines, '')
  endfor
  call add(a:lines, '')
endfunction
"}}}
"==================
"gatherer
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
function! s:_add_var(variables, var) "{{{
  let a:variables[a:var] = get(a:variables, a:var, {'vals': [], 'is_dict': 0,})
  return a:variables[a:var]
endfunction
"}}}
function! s:_join_val_line_continuation(val, lines, idx) "{{{
  let val = substitute(a:val, '^\s*', '', '')
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
"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
