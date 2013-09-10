command! -nargs=*   VimHelpGenerator    call vimhelpgenerator#generate(0, <f-args>)
command! -nargs=*   VimHelpGeneratorVirtual    call vimhelpgenerator#generate(1, <f-args>)
