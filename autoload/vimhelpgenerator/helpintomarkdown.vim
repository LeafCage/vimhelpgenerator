if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
scriptencoding utf-8
"=============================================================================
function! vimhelpgenerator#helpintomarkdown#generate(bgnrow, lastrow)
  if &ft!=#'help'
    echoh WarningMsg| ec 'helpファイルの中で実行して下さい'| echoh NONE
    return
  end
  let lines = getline(a:bgnrow, a:lastrow)
  call map(lines, 'substitute(v:val, ''|\([][0-9A-Za-z_+=;:,.''''<>(){}@!#$%&^~\-\\]\+\)|'', "`\\1`", "g")')
  let lines = s:_codeblock(lines)
  let lines = s:_append_subhead(lines)
  let lines = s:_append_head(lines)
  let lines = s:_insertspaceline_before_li(lines)
  let lines = s:_join_nl(lines)
  call map(lines, 'substitute(v:val, ''^\s\+\ze[^-]'', "", "")')

  let path = expand('%:p:h:h'). '/README.md'
  if !filereadable(path)
    let _ = matchlist(getline(1), '^\*\(\w\+\)\.txt\*\s*\(.*\)')
    let [pluginname, plugininfo] = [ _[1], substitute(_[2], '|\([][0-9A-Za-z_+=;:,.''<>(){}@!#$%&^~\-\\]\+\)|', '`\1`', 'g') ]
    call extend(lines, ['#'.pluginname.'.vim', plugininfo, ''], 0)
  end
  let @" = join(lines, "\n")
  exe 'edit' path
endfunction


"======================================
function! s:_codeblock(lines) "{{{
  let [lineslen, i] = [len(a:lines), 0]
  while i < lineslen
    let a:lines[i] = substitute(a:lines[i], '<\(.\{-}\)>', '\&lt;\1\&gt;', 'g')
    if a:lines[i] !~ '>$'
      let i+=1
      continue
    end
    let a:lines[i] = substitute(a:lines[i], '\s*>$', '', '')
    call extend(a:lines, ['', '```vim'], i+1)
    let lineslen+=2
    let i+=3
    while i<lineslen && a:lines[i]=~'^\s'
      let i+=1
    endwhile
    call extend(a:lines, ['```', ''], i)
    let lineslen+=2
    let i+=2
    if i < lineslen
      let a:lines[i] = substitute(a:lines[i], '^<', '', '')
    end
  endwhile
  return a:lines
endfunction
"}}}
"==================
function! s:_append_subhead(lines) "{{{
  let [lineslen, i] = [len(a:lines), 0]
  while i < lineslen
    if a:lines[i]=~'^\s*\*.*\*'
    elseif a:lines[i]=~'^\s*\*\|\s*\~$'
      let a:lines[i] = substitute(substitute(a:lines[i], '^\s*\*\s*\|\s*\~$', '', 'g'), '^', '####', '')
      let a:lines[i] = substitute(a:lines[i], '^\s*\*\*\s*', '#####', '')
      let a:lines[i] = substitute(a:lines[i], '^\s*\*\*\*\s*', '######', '')
    end
    let i+=1
  endwhile
  return a:lines
endfunction
"}}}
"==================
let s:TAG_PAT = '\s\+\*[0-9A-Za-z_:()-]\+\*$'
function! s:_append_head(lines) "{{{
  let [lineslen, i] = [len(a:lines), 0]
  while i < lineslen
    if a:lines[i]=~'\S.\{-}'.s:TAG_PAT
      let a:lines[i] = substitute(a:lines[i], '\(\S.\{-}\)'.s:TAG_PAT, '###\1', '')
      let lineslen -= s:__rm_nextspacelines(a:lines, i)
      let i+=1
      continue
    elseif a:lines[i]!~'^=\{78}\|^-\{78}'
      let i+=1
      continue
    end
    while 1
      if i+1>=lineslen-1 || a:lines[i+1]!~'^\s*$'
        break
      end
      call remove(a:lines, i+1)
    endwhile
    let head = a:lines[i]=~'^=\+' ? '##' : '###'
    if a:lines[i+1]=~'\S.\{-}'.s:TAG_PAT
      let a:lines[i+1] = substitute(a:lines[i+1], '\(\S.\{-}\)'.s:TAG_PAT, head.'\1', '')
      let lineslen -= s:__rm_nextspacelines(a:lines, i+1)
    end
    call remove(a:lines, i)
    let lineslen -= 1
  endwhile
  return a:lines
endfunction
"}}}
function! s:__rm_nextspacelines(lines, idx) "{{{
  let i = a:idx+1
  let rmd = 0
  while 1
    if get(a:lines, i) !~'^\s*$'
      break
    end
    call remove(a:lines, i)
    let i+=1
    let rmd+=1
  endwhile
  return rmd
endfunction
"}}}
"==================
function! s:_insertspaceline_before_li(lines) "{{{
  let [lineslen, i] = [len(a:lines), 0]
  while i < lineslen
    if a:lines[i] !~ '^\s*\%(-\|\d\+\.\)\s'
      let i+=1
      continue
    end
    call insert(a:lines, '', i)
    let lineslen+=1
    let i+=1
    while i<lineslen && a:lines[i]!~'^\s*$'
      let i+=1
    endwhile
  endwhile
  return a:lines
endfunction
"}}}
"==================
let s:NL_LIMEN = 68
function! s:_join_nl(lines) "{{{
  let [lineslen, i] = [len(a:lines), -1]
  while i < lineslen-1
    let i+=1
    if a:lines[i]=~'^\s*$\|^##'
      continue
    elseif a:lines[i]=~'^\s*\%(-\|\d\+\.\)\s'
      while i<lineslen && a:lines[i]!~'^\s*$'
        let i+=1
      endwhile
      continue
    elseif a:lines[i]=~'^```vim'
      while i<lineslen && a:lines[i]!='```'
        let i+=1
      endwhile
      continue
    elseif strdisplaywidth(a:lines[i]) < s:NL_LIMEN
      let a:lines[i] .= '  '
      continue
    elseif get(a:lines, i+1)=~'^$\|^##\|^\s*-\s\|^```'
      let a:lines[i] .= '  '
      continue
    end
    let a:lines[i] .= s:__substitute_joinline(get(a:lines, i+1, ''))
    while strdisplaywidth(get(a:lines, i+1, '')) >= s:NL_LIMEN
      let a:lines[i] .= s:__substitute_joinline(get(a:lines, i+2, ''))
      call remove(a:lines, i+1)
      let lineslen -= 1
    endwhile
    if i+1 < lineslen
      call remove(a:lines, i+1)
      let lineslen -= 1
    end
    let a:lines[i] .= '  '
  endwhile
  return a:lines
endfunction
"}}}
function! s:__substitute_joinline(nextline) "{{{
  let sub = byteidx(matchstr(a:nextline, '^\s*\zs\S'), 1)>1 ? '' : ' '
  return substitute(a:nextline, '^\s*', sub, '')
endfunction
"}}}

"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
