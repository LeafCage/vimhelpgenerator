command! -nargs=*   VimHelpGenerator    call vimhelpgenerator#generate(0, <f-args>)
command! -nargs=*   VimHelpGeneratorVirtual    call vimhelpgenerator#generate(1, <f-args>)
aug vimhelpgenerator
  autocmd!
  autocmd FileType help   command! -nargs=0 -range -buffer   HelpIntoMarkdown    call vimhelpgenerator#helpintomarkdown#generate(<line1>, <line2>)
aug END
