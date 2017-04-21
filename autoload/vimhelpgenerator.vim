if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
scriptencoding utf-8
"=============================================================================
let g:vimhelpgenerator_virtualhelpopencmd = get(g:, 'vimhelpgenerator_virtualhelpopencmd', 'split')
let g:vimhelpgenerator_version = get(g:, 'vimhelpgenerator_version', 'Version :')
let g:vimhelpgenerator_author = get(g:, 'vimhelpgenerator_author', 'Author  :')
let g:vimhelpgenerator_license = get(g:, 'vimhelpgenerator_license', 'vimhelpgenerator/MIT')
let g:vimhelpgenerator_gitignore_lines = get(g:, 'vimhelpgenerator_gitignore_lines', ['/doc/tags*'])
let g:vimhelpgenerator_uri = get(g:, 'vimhelpgenerator_uri', 'https://github.com/user/')
let g:vimhelpgenerator_modeline = get(g:, 'vimhelpgenerator_modeline', 'vim:tw=78:ts=8:ft=help:norl:noet:fen:')
let g:vimhelpgenerator_defaultlanguage = get(g:, 'vimhelpgenerator_defaultlanguage', 'ja')
let g:vimhelpgenerator_defaultoverrider = get(g:, 'vimhelpgenerator_defaultoverrider', 'default')
let s:vimhelpgenerator_contents = {'contents': 1, 'introduction': 1, 'usage': 1,
  \ 'interface': 1, 'variables': 1, 'commands': 1, 'key-mappings': 1, 'functions': 1,
  \ 'setting': 0, 'todo': 1, 'changelog': 1,}
let g:vimhelpgenerator_contents = get(g:, 'vimhelpgenerator_contents', {})
call extend(g:vimhelpgenerator_contents, s:vimhelpgenerator_contents, 'keep')
unlet s:vimhelpgenerator_contents

"=============================================================================
aug vimhelpgenerator
  au!
  au VimLeavePre *    call <SID>_clear_virtualbufs()
aug END
"==================
let s:Generator = {}
function! s:newGenerator(overrider_name, elements)
  let generator = {'name': a:elements.name, 'root': a:elements.root, 'variables': {}, 'commands': {}, 'globalkeymappings': {}, 'localkeymappings': {}, 'functions': {}, 'words': (g:vimhelpgenerator_defaultlanguage==?'ja' ? s:_ja_words() : s:_en_words()), 'lang': g:vimhelpgenerator_defaultlanguage}
  call extend(generator, a:elements.elements)
  call extend(generator, s:Generator, 'keep')
  try
    call extend(generator, vimhelpgenerator#overrider#{a:overrider_name}#generator())
  catch /E117/
    echohl WarningMsg
    echo 'VimHelpGenerator: invalid overrider name > '. a:overrider_name
    echohl NONE
  endtry
  return generator
endfunction
function! s:Generator.make_gitignore() "{{{
  if g:vimhelpgenerator_gitignore_lines==[]
    return
  end
  let gitignore_file = self.root. '/.gitignore'
  if !filereadable(gitignore_file)
    call writefile(g:vimhelpgenerator_gitignore_lines, gitignore_file)
  endif
endfunction
"}}}
function! s:Generator.exists_helpfile_already() "{{{
  let helpdir = self.root. '/doc'
  let helppath = helpdir. '/'. self.name. (self.lang ==? 'ja' ? '.jax': '.txt')
  let ret = filereadable(helppath)
  if ret
    echoh WarningMsg| call input('helpファイルはすでに存在します。仮想バッファで出力します。', )| echoh NONE
  end
  return ret
endfunction
"}}}
function! s:Generator.make_helpfile(lines) "{{{
  let helpdir = self.root. '/doc'
  let helppath = helpdir. '/'. self.name. (self.lang ==? 'ja' ? '.jax': '.txt')
  if !isdirectory(helpdir)
    call mkdir(helpdir, 'p')
  endif
  call writefile(a:lines, helppath)
  return helppath
endfunction
"}}}
function! s:Generator.open_virtualhelp(lines) "{{{
  let is_finded = 0
  for winnr in range(1, winnr('$'))
    if getbufvar(winbufnr(winnr), 'vimhelpgenerator_virtualbuffer') != ''
      exe winnr. 'wincmd w'
      let is_finded = 1
      break
    endif
  endfor
  if !is_finded && g:vimhelpgenerator_virtualhelpopencmd =~ 'sp\%[lit]\|vs\%[plit]\|new\|vne\%[w]\|sv\%[iew]'
    silent exe g:vimhelpgenerator_virtualhelpopencmd
  endif
  silent exe printf('keepj edit +se\ noro\ bt=nofile\ ft=help\ tw=78\ ts=8\ noet :[%s%s]', self.name, (self.lang ==? 'ja' ? '.jax': '.txt'))
  let b:vimhelpgenerator_virtualbuffer = 1
  call add(s:virtualhelp_bufnrs, bufnr('%'))
  let save_ul = &undolevels
  setl undolevels=-1
  silent %delete _
  call append(1, a:lines)
  silent delete _
  let &l:ul = save_ul
endfunction
"}}}
function! s:Generator.build_helplines() "{{{
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
function! s:Generator._contents() "{{{
  let lines = ['', self.sep_l, self._caption(self.words.contents, 'contents'), '',]
  let contents = self._contentskeys()
  for c in filter(contents, 'v:val!="contents"')
    call add(lines, self._contents_caption(self.words[c], c, (c=~'s$'?'  ':'')))
  endfor
  call extend(lines, ['', ''])
  return lines
endfunction
"}}}
function! s:Generator._introduction() "{{{
  let latest_ver_lines = g:vimhelpgenerator_uri=='' ? [] : [self.words['latest-version'], g:vimhelpgenerator_uri. self.name. '.vim']
  let lines = [self.sep_l, self._caption(self.words.introduction, 'introduction'), '', printf(self.words.introduction_preface, self.name), '']
  call extend(lines, latest_ver_lines)
  call extend(lines, ['', ''])
  return lines
endfunction
"}}}
function! s:Generator._usage() "{{{
  let lines = [self.sep_l, self._caption(self.words.usage, 'usage'), '', '', '']
  return lines
endfunction
"}}}
function! s:Generator._interface() "{{{
  let lines = [self.sep_l, self._caption(self.words.interface, 'interface'), '']
  return lines
endfunction
"}}}
function! s:Generator._variables() "{{{
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
function! s:Generator._commands() "{{{
  let lines = [self.sep_s, self._caption(self.words.commands, 'commands'), '']
  let globalcmds = filter(copy(self.commands), '!v:val.is_buflocal')
  call self.__append_commands_lines(lines, globalcmds)
  let buflocalcmds = filter(copy(self.commands), 'v:val.is_buflocal')
  call self.__append_commands_lines(lines, buflocalcmds)
  return lines
endfunction
"}}}
function! s:Generator._keymappings() "{{{
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
function! s:Generator._functions() "{{{
  let lines = [self.sep_s, self._caption(self.words.functions, 'functions'), '']
  let globalfuncs = keys(filter(copy(self.functions), 'v:val.is_global'))
  for func in sort(globalfuncs)
    call extend(lines, self._interface_caption(printf('%s(%s)', func, self.functions[func].param), func.'()'))
    call extend(lines, ['', ''])
  endfor
  return lines
endfunction
"}}}
function! s:Generator._setting() "{{{
  let lines = [self.sep_l, self._caption(self.words.setting, 'setting'), '']
  return lines
endfunction
"}}}
function! s:Generator._todo() "{{{
  let lines = [self.sep_l, self._caption(self.words.todo, 'todo'), '', '', '']
  return lines
endfunction
"}}}
function! s:Generator._changelog() "{{{
  let lines = [self.sep_l, self._caption(self.words.changelog, 'changelog'), '', '']
  return lines
endfunction
"}}}

"========================================================
"Main:
function! vimhelpgenerator#generate(is_virtual, ...)
  let path = fnamemodify(expand(get(a:, 2, '%')), ':p')
  let inference = __vimhelpgenerator#lim#misc#infer_plugin_pathinfo(path)
  if inference=={}
    echohl WarningMsg |echo 'VimHelpGenerator: failed.' |echohl NONE
    return {'mes': 'VimHelpGenerator: failed.'}
  end
  let pluginname = s:confirm(inference)
  if pluginname==''
    return {'mes': 'canceled'}
  endif
  redraw

  let elements = __vimhelpgenerator#lim#alzplugin#analyze(inference.root, pluginname, ['variables', 'commands', 'keymappings', 'functions'])
  let overrider_name = get(a:, 1, '""')
  let overrider_name = overrider_name=~'^[''"]\+$' ? g:vimhelpgenerator_defaultoverrider : overrider_name
  let generator = s:newGenerator(overrider_name, elements)
  let lines = generator.build_helplines()
  if a:is_virtual || generator.exists_helpfile_already()
    call generator.open_virtualhelp(lines)
  else
    call generator.make_gitignore()
    let path = generator.make_helpfile(lines)
    silent exe 'edit '. path
  endif
  return generator
endfunction



"======================================
"main
function! s:confirm(inference) "{{{
  let input = input(printf('%s  "%s"  [e]xecute/[r]ename/[q]uit: ', a:inference.root, a:inference.name), '', )
  if input == 'r'
    let name = input('input plugin-name: ', a:inference.name)
    return name
  elseif input==#'e'
    return a:inference.name
  endif
  return ''
endfunction
"}}}
"autocmd
let s:virtualhelp_bufnrs = []
function! s:_clear_virtualbufs() "{{{
  for bufnr in s:virtualhelp_bufnrs
    if buflisted(bufnr)
      call setbufvar(bufnr, "&bl", 0)
    endif
  endfor
endfunction
"}}}
"==================
"generator
function! s:_ja_words() "{{{
  return {'summary': '日本語ヘルプ', 'contents': '目次', 'introduction': '概要', 'introduction_preface': '*%s* は',
    \ 'latest-version': '最新版:', 'usage': '使い方', 'interface': 'インターフェイス',
    \ 'variables': '変数', 'default-value': '既定値: ', 'commands': 'コマンド', 'buffer-local-command': 'バッファローカルなコマンド',
    \ 'lines': '行', 'default': '既定:', 'whole-file': 'ファイル全体', 'key-mappings': 'キーマッピング', 'availablemode': '有効モード',
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
    \ 'lines': 'lines', 'default': 'default:', 'whole-file': 'whole file', 'key-mappings': 'KEY-MAPPINGS', 'availablemode': 'available mode',
    \ 'buffer-local-mapping': 'buffer local mapping', 'defaultmappings_global': 'default mappings (global)', 'defaultmappings_local': 'default mapping (buffer local)', 'defaultmappings': 'default mappings', 'localdefaultmappings': 'local default mappings',
    \ 'modeshortname': {'n': 'normal', 'x': 'visual', 's': 'select', 'o': 'operator', 'i': 'insert', 'c': 'commandline'},
    \ 'modename': {'n': 'normal mode', 'x': 'visual mode', 's': 'select mode', 'o': 'operator mode', 'i': 'insert mode', 'c': 'commandline'},
    \ 'functions': 'FUNCTIONS', 'setting': 'SETTING', 'todo': 'TODO', 'changelog': 'CHANGELOG', }
endfunction
"}}}
function! s:Generator._caption(title, tag) dict "{{{
  let tabnum = 6 - (strdisplaywidth(a:title) / 8)
  return printf('%s%s*%s-%s*', a:title, repeat("\t", tabnum), self.name, a:tag)
endfunction
"}}}
function! s:Generator._interface_caption(title, tag) "{{{
  let tag = substitute(a:tag, '\*', 'star', 'g')
  let titlelen = strdisplaywidth(a:title)
  let taglen = strdisplaywidth(tag)
  if taglen <= 28 && titlelen <= 40
    let tabnum = 6 - (titlelen / 8)
    return [printf('%s%s*%s*', a:title, repeat("\t", tabnum), tag)]
  elseif taglen > 28 && titlelen < 39
    let tabnum = 5 - (titlelen / 8)
    return [printf('%s%s*%s*', a:title, repeat("\t", tabnum), tag)]
  else
    let tabnum = (78 - taglen - 2) / 8
    return [printf('%s*%s*', repeat("\t", tabnum > 6 ? 6 : tabnum), tag), a:title]
  endif
endfunction
"}}}
function! s:Generator._contentskeys() "{{{
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
"make_helpfile contents
function! s:Generator._contents_caption(title, tag, ...) dict "{{{
  let padding = get(a:, 1, '')
  let tabnum = 4 - (strdisplaywidth(padding. a:title) / 8)
  return printf('%s%s%s%s|%s-%s|', padding, a:title, repeat("\t", tabnum), padding, self.name, a:tag)
endfunction
"}}}
"make_helpfile variables
function! s:_sort_variables(item1, item2) "{{{
  return a:item1[1].order - a:item2[1].order
endfunction
"}}}
"make_helpfile commands
function! s:Generator.__append_commands_lines(lines, commands) "{{{
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
function! s:Generator._build_commandhelpstr(cmd) "{{{
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
"make_helpfile keymappings
function! s:Generator.__append_keymapping_lines(lines, keymappings, is_local) "{{{
  let baflocal_label = a:is_local ? ["\t". self.words['buffer-local-mapping']] : []
  let lhss = map(sort(filter(items(a:keymappings), 'v:val[0] =~? ''^<Plug>\|<Leader>\|<LocalLeader>'''), 's:_sort_lhs'), 'v:val[0]')
  for lhs in lhss
    call extend(a:lines, self._interface_caption(lhs, lhs))
    call extend(a:lines, baflocal_label)
    let validmodes = "\t". self.words.availablemode. ":"
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
function! s:Generator.__append_defaultkeymappinglist_lines(lines, defaultkeymappings, is_local) "{{{
  if a:defaultkeymappings == {}
    return
  endif
  call add(a:lines, (a:is_local ? self.words.localdefaultmappings : self.words.defaultmappings))
  for m in ['n', 'i', 'x', 's', 'o', 'c']
    let lhss = sort(keys(filter(copy(a:defaultkeymappings), 'has_key(v:val, m)')))
    if lhss == []
      continue
    endif
    call filter(map(lhss, '[v:val, strdisplaywidth(v:val) / 8]'), 'v:val[1] < 2')
    if lhss==[]
      continue
    end
    call extend(a:lines, [self.words.modename[m], "{lhs}\t\t{rhs}", "--------\t------------------------"])
    for lhs in lhss
      call add(a:lines, lhs[0]. repeat("\t", (2 - lhs[1])). join(a:defaultkeymappings[lhs[0]][m].rhs))
    endfor
    call add(a:lines, '')
  endfor
  call add(a:lines, '')
endfunction
"}}}
"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
