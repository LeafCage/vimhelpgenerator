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
  let maker = {'name': '', 'rootpath': '', 'is_failinit': 0, 'variables': {}, 'commands': {}, 'globalkeymappings': {'n': {}, 'i': {}, 'c': {}, 'o': {}, 'x': {}, 's': {}}, 'localkeymappings': {'n': {}, 'i': {}, 'c': {}, 'o': {}, 'x': {}, 's': {}}, 'keymappings_index': {'rhs': [], 'buflocal': [], 'mode': [], 'lhs': []}, 'functions': {}}
  call extend(maker, s:maker, 'keep')
  call maker._set_rootpath_and_name(a:path)
  return maker
endfunction
function! s:maker._set_rootpath_and_name(path) "{{{
  for dir in ['after', 'autoload', 'syntax', 'ftplugin', 'ftdetect']
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
  let self.filepaths = split(pluginpaths. "\n". autoloadpaths. "\n". autoloadfile, '\n')
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
  for m in ['n', 'i', 'c', 'o', 'x', 's']
    call map(self.localkeymappings[m], 's:_combine_keymappings(a:gatherer.localkeymappings[m], v:key, v:val)')
    call extend(self.localkeymappings[m], a:gatherer.localkeymappings[m], 'keep')
    try
      call extend(self.globalkeymappings[m], a:gatherer.globalkeymappings[m], 'error')
    catch /E737/
      echoerr 'vimhelpmaker: 同じグローバルキーマップが複数定義されています。'. v:exception
    endtry
  endfor
  call extend(self.keymappings_index.rhs, a:gatherer.keymappings_index.rhs)
  call extend(self.keymappings_index.buflocal, a:gatherer.keymappings_index.buflocal)
  call extend(self.keymappings_index.mode, a:gatherer.keymappings_index.mode)
  call extend(self.keymappings_index.lhs, a:gatherer.keymappings_index.lhs)
  call extend(self.functions, a:gatherer.functions, 'keep')
endfunction
"}}}
function! s:maker.set_default_keymappings() "{{{
  for lhs in self.keymappings_index.lhs
    if lhs =~? '^<Plug>'
      call s:_find_pluginmapping_from_rhss(lhs, self.globalkeymappings, self.localkeymappings, self.keymappings_index)
    endif
  endfor
  unlet self.keymappings_index
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
    call add(lines, '')
    call add(lines, '')
  endfor
  return lines
endfunction
"}}}
function! s:maker._commands() "{{{
  let lines = [self.sep_s, self.caption(self.lang.commands, 'commands'), '']
  let globalcmds = filter(copy(self.commands), '!v:val.buflocal')
  call s:_add_commandhelpstr(lines, sort(keys(globalcmds)), self)
  let buflocalcmds = filter(copy(self.commands), 'v:val.buflocal')
  if buflocalcmds == {}
    return lines
  endif
  call extend(lines, [self.sep_s, self.caption(self.lang['buffer-local-commands'], 'buffer-local-commands'), ''])
  call s:_add_commandhelpstr(lines, sort(keys(buflocalcmds)), self)
  return lines
endfunction
"}}}
function! s:maker._keymappings() "{{{
  let sep_ss = repeat('-', 39)
  let lines = [self.sep_s, self.caption(self.lang['key-mappings'], 'key-mappings'), '']
  for m in ['n', 'x', 's', 'o', 'i', 'c']
    let lhss = filter(keys(self.globalkeymappings[m]), 'v:val =~ "^<Plug>"')
    if lhss == []
      continue
    endif
    call extend(lines, [sep_ss, self.lang.modecaption[m], ''])
    for lhskey in sort(lhss)
      call extend(lines, self.interface(lhskey, lhskey))
      for mapping in self.globalkeymappings[m][lhskey].defaultmappings
        call add(lines, "\t". self.lang.defaultmapping. mapping)
      endfor
      call extend(lines, ['', ''])
    endfor
  endfor
  for m in ['n', 'x', 's', 'o', 'i', 'c']
    let lhss = filter(keys(self.localkeymappings[m]), 'v:val =~ "^<Plug>"')
    if lhss == []
      continue
    endif
    call extend(lines, [sep_ss, self.lang.modecaption[m], ''])
    for lhskey in sort(lhss)
      call extend(lines, self.interface(lhskey, lhskey))
      for lhsdict in self.localkeymappings[m][lhskey]
        for mapping in lhsdict.defaultmappings
          call add(lines, "\t". self.lang.defaultmapping. mapping)
        endfor
      endfor
      call extend(lines, ['', ''])
    endfor
  endfor
  return lines
endfunction
"}}}
function! s:maker._functions() "{{{
  let lines = [self.sep_s, self.caption(self.lang.functions, 'functions'), '']
  let globalfuncs = keys(filter(copy(self.functions), 'v:val.global'))
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

function! s:maker.make_readme() "{{{
endfunction
"}}}
"==================
let s:gatherer = {}
function! s:new_gatherer(path, rootpath)
  let gatherer = {'variables': {}, 'commands': {}, 'globalkeymappings': {'n': {}, 'i': {}, 'c': {}, 'o': {}, 'x': {}, 's': {}}, 'localkeymappings': {'n': {}, 'i': {}, 'c': {}, 'o': {}, 'x': {}, 's': {}}, 'keymappings_index': {'rhs': [], 'buflocal': [], 'mode': [], 'lhs': []}, 'functions': {},}
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
  if options.buflocal
    for m in ['n', 'i', 'c', 'o', 'x', 's']
      if mode[m]
        let self.localkeymappings[m][lhs] = get(self.localkeymappings[m], lhs, [])
        call add(self.localkeymappings[m][lhs], extend({'remap': remap, 'rhs': rhs, 'mode': mode, 'defaultmappings': []}, options))
      endif
    endfor
  else
    for m in ['n', 'i', 'c', 'o', 'x', 's']
      if mode[m]
        let self.globalkeymappings[m][lhs] = extend({'remap': remap, 'rhs': rhs, 'mode': mode, 'defaultmappings': []}, options)
      endif
    endfor
  endif
  call add(self.keymappings_index.rhs, rhs)
  call add(self.keymappings_index.buflocal, options.buflocal)
  call add(self.keymappings_index.mode, mode)
  call add(self.keymappings_index.lhs, lhs)
endfunction
"}}}
function! s:gatherer._add_functions(idx) "{{{
  let linestr = self.lines[a:idx]
  let func = matchlist(linestr, '^\s*fu\%[nction]!\?\s\+\(.\+\)(\(.*\))')
  if func == []
    return
  endif
  let [funcname, param] = func[1:2]
  let self.functions[funcname] = {'param': substitute(param, '\w\+\|\.\.\.', '{\0}', 'g')}
  let self.functions[funcname].global = funcname =~ '^\u\|^[^s]:'. (self.autoload_prefix == '' ? '' : '\|'. self.autoload_prefix)
  let self.functions[funcname].dict = funcname =~ '\.\|\['
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
"set_default_keymappings()
function! s:_find_pluginmapping_from_rhss(pluginmapping, globalkeymappings, localkeymappings, keymappings_index) "{{{
  let i = 1
  while 1
    let idx = match(a:keymappings_index.rhs, a:pluginmapping, 0, i)
    if idx == -1
      return
    endif
    let findedrhs_mode = a:keymappings_index.mode[idx]
    let findedrhs_lhskey = a:keymappings_index.lhs[idx]
    if a:keymappings_index.buflocal[idx]
      for m in ['n', 'i', 'c', 'o', 'x', 's']
        if !findedrhs_mode[m] || !has_key(a:localkeymappings[m], a:pluginmapping)
          continue
        endif
        for lhs in a:localkeymappings[m][a:pluginmapping]
          if index(lhs.defaultmappings, findedrhs_lhskey) == -1
            call add(lhs.defaultmappings, findedrhs_lhskey)
          endif
        endfor
      endfor
    else
      for m in ['n', 'i', 'c', 'o', 'x', 's']
        if !findedrhs_mode[m] || !has_key(a:globalkeymappings[m], a:pluginmapping)
          continue
        endif
        if index(a:globalkeymappings[m][a:pluginmapping].defaultmappings, findedrhs_lhskey) == -1
          call add(a:globalkeymappings[m][a:pluginmapping].defaultmappings, findedrhs_lhskey)
        endif
      endfor
    endif
    let i += 1
  endwhile
endfunction
"}}}
"make_help
function! s:_ja_lang() "{{{
  return {'contents': '目次', 'introduction': '概要', 'introduction_preface': '*%s* は～するVimプラグインです。',
    \ 'requirements': '要件:', 'latest-version': '最新版:', 'usage': '使い方', 'interface': 'インターフェイス',
    \ 'variables': '変数', 'default': '既定: ', 'commands': 'コマンド', 'buffer-local-commands': 'バッファローカルコマンド',
    \ 'lines': '行', 'whole-file': 'ファイル全体', 'key-mappings': 'キーマッピング', 'defaultmapping': 'デフォルトマッピング: ',
    \ 'modecaption': {'n': 'ノーマルモードマッピング', 'x': 'ビジュアルモードマッピング', 's': 'セレクトモードマッピング',
    \ 'o': 'オペレータモードマッピング', 'i': 'インサートモードマッピング', 'c': 'コマンドラインマッピング'},
    \ 'enable': '有効', 'n': 'ノーマル', 'x': 'ビジュアル', 's': 'セレクト', 'o': 'オペレータ', 'i': 'インサート', 'c': 'コマンドライン', 'buffer-local-mapping': 'バッファローカル',
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
  if strdisplaywidth(a:tag) <= 28 && strdisplaywidth(a:title) <= 40
    let tabnum = 6 - (strdisplaywidth(a:title) / 8)
    return [printf('%s%s*%s*', a:title, repeat("\t", tabnum), a:tag)]
  else
    let tabnum = (78 - strdisplaywidth(a:tag) - 2) / 8
    return [printf('%s*%s*', repeat("\t", tabnum > 6 ? 6 : tabnum), a:tag), a:title]
  endif
endfunction
"}}}
function! s:_add_commandhelpstr(lines, commands, this) "{{{
  for cmd in a:commands
    let [command, description] = s:_commandhelpstr(cmd, a:this)
    call extend(a:lines, a:this.interface(command, ':'. cmd))
    if description != ''
      call add(a:lines, description)
    endif
    call extend(a:lines, ['', ''])
  endfor
endfunction
"}}}
function! s:_commandhelpstr(cmd, this) "{{{
  let command = ':'
  let description = ''
  if a:this.commands[a:cmd].range.range != ''
    let command .= '[range]'
    let description = '[range] '. a:this.lang.lines. ' ('. a:this.lang.default. a:this.commands[a:cmd].range.range=='%' ? self.lang['whole-file'] : a:this.commands[a:cmd].range.range. ')'
  endif
  if a:this.commands[a:cmd].range.count != ''
    let command .= '[count]'
    let description = '[count] ('. a:this.lang.default. a:this.commands[a:cmd].range.count. ')'
  endif
  let command .= a:cmd
  if a:this.commands[a:cmd].bang
    let command .= '[!]'
  endif
  if a:this.commands[a:cmd].register
    let command .= ' [x]'
  endif
  if a:this.commands[a:cmd].nargs == 1
    let command .= ' {}'
  elseif a:this.commands[a:cmd].nargs == '?'
    let command .= ' [{}]'
  elseif a:this.commands[a:cmd].nargs == '+'
    let command .= ' {} ...'
  elseif a:this.commands[a:cmd].nargs == '*'
    let command .= ' [{} ...]'
  endif
  return [command, description]
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
  let attr = {'nargs': '', 'range': {}, 'bang': 0, 'register': 0, 'buflocal': 0}
  let attr.nargs = matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-nargs=\zs.')
  let attr.range.count = matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-count\s') ? 0 : matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-count=\zs\d\+')
  let attr.range.range = matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-range\s') ? 'current line' : matchstr(a:linestr, 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-range=\zs\S\+')
  let attr.bang = a:linestr =~ 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-bang' ? 1 : 0
  let attr.register = a:linestr =~ 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-register' ? 1 : 0
  let attr.buflocal = a:linestr =~ 'com\%[mand]!\?\s\+\%(-.\+\s\+\)*-buffer' ? 1 : 0
  return attr
endfunction
"}}}
"keymappings
function! s:_mapcommand(linestr) "{{{
  return matchstr(a:linestr, '^\s*\zs\%([nvxoic]m\%[ap]\|s\?map!\?\|[oic]\?no\%[remap]!\?\|[nvx]n\%[oremap]\|snor\%[emap]\)\ze\s')
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
  let options = {'buflocal': 0, 'silent': 0, 'unique': 0, 'expr': 0}
  let optionsstr = matchstr(a:linestr, '\%(\%(<buffer>\|<silent>\|<expr>\|<unique>\|<special>\|<script>\)\s*\)\+')
  let options.buflocal = optionsstr=~'<buffer>'
  let options.silent = optionsstr=~'<silent>'
  let options.unique = optionsstr=~'<unique>'
  let options.expr = optionsstr=~'<expr>'

  let lhs = matchstr(a:linestr, a:mapcommand. '\s\+'. optionsstr. '\zs\S\+')
  let rhs = matchstr(a:linestr, a:mapcommand. '\s\+'. optionsstr. escape(lhs, '~$.*\'). '\s\+\zs.\+')
  let lhs = s:_keymap_uppercase_substitute(lhs)
  let rhs = s:_keymap_uppercase_substitute(rhs)
  return [options, lhs, rhs]
endfunction
"}}}
function! s:_keymap_uppercase_substitute(str) "{{{
  return substitute(a:str, '<\(\u\)\(\a\{2,}\)>', '<\1\L\2\E>', 'g')
endfunction
"}}}
"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
