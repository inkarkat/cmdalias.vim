" cmdalias.vim: Create aliases for Vim commands.
" Author: Hari Krishna Dara (hari.vim at gmail dot com)
" Contributors: Ingo Karkat (swdev at ingo-karkat dot de)
"               - Replace :cabbr with separate alias implementation. 
"               - Support more cmd prefixes. 
" Last Change: 12-Sep-2011
" Created:     07-Jul-2003
" Requires: Vim-7.0 or higher
" Version: 4.1.0
" Licence: This program is free software; you can redistribute it and/or
"          modify it under the terms of the GNU General Public License.
"          See http://www.gnu.org/copyleft/gpl.txt 
" Download From:
"     http://www.vim.org/script.php?script_id=745
" Usage:
"     :call CmdAlias('<lhs>', '<rhs>', [flags])
"     or
"     :Alias <lhs> <rhs> [flags]
"
"     :UnAlias <lhs> ...
"     :Aliases [<lhs> ...]
"
" Ex:
"     :Alias runtime Runtime
"     :Alias find Find
"     :Aliases
"     :UnAlias find
"
" Description:
"   - Vim doesn't allow us to create user-defined commands unless they start
"     with an uppercase letter. I find this annoying and constrained when it
"     comes to overriding built-in commands with my own. To override built-in
"     commands, we often have to create a new command that has the same name
"     as the built-in but starting with an uppercase letter (e.g., "Cd"
"     instead of "cd"), and remember to use that every time (besides the
"     fact that typing uppercase letters take more effort). An alternative is
"     to use the :cabbr to create an abbreviation for the built-in command
"     (:cmap is not good) to the user-defined command (e.g., "cabbr cd Cd").
"     But this would generally cause more inconvenience because the
"     abbreviation gets expanded no matter where in the command-line you use
"     it. Also, abbreviations of type "full-id" must be delimited by whitespace
"     or non-keyword characters, which prevents expansion if ranges like "42" or
"     "/foo/" are directly prepended to the alias. 
"     This is where the plugin comes to your rescue by hooking into the
"     command-line and implementing its own alias expansion. Aliases are only
"     expanded if they are in command position, i.e. at the beginning of the
"     command line, or after a "|" command-separator. This takes into account
"     ranges, command bang and certain prefix commands. 
"   - The plugin provides commands to define, list and undefine command-line
"     aliases. You can pass an optional flag "<buffer>" to make the alias local
"     to the current buffer. 
" Drawbacks:
"   - If the <rhs> is not of the same size as <lhs>, the in-place expansion
"     feels odd.
"   - Since the expansion is in-place, Vim command-line history saves the
"     <rhs>, not the <lhs>. This means, you can't retrieve a command from
"     history by partially typing the <lhs> (you have to instead type the
"     <rhs> for this purpose).

if exists("loaded_cmdalias")
  finish
endif
if v:version < 700
  echomsg "cmdalias: You need Vim 7.0 or higher"
  finish
endif
let loaded_cmdalias = 300

" Make sure line-continuations won't cause any problem. This will be restored
"   at the end
let s:save_cpo = &cpo
set cpo&vim

if !exists('g:cmdaliasCmdPrefixes')
  let g:cmdaliasCmdPrefixes = 'verbose debug silent redir vertical leftabove aboveleft rightbelow belowright topleft botright argdo bufdo tab tabdo windo'
endif
let s:cmdPrefixesExpr = '\%('.
\ join(
\   map(
\     split(g:cmdaliasCmdPrefixes),
\     'v:val.''!\?\s\+'''
\   ),
\   '\|'
\ ).
\ '\)\+'

command! -nargs=+ Alias :call CmdAlias(<f-args>)
command! -nargs=* UnAlias :call UnAlias(<f-args>)
command! -nargs=* Aliases :call <SID>Aliases(<f-args>)

if ! exists('s:aliases')
  let s:aliases = {}
endif

" Define a new command alias.
function! CmdAlias(lhs, ...)
  let lhs = a:lhs
  if lhs !~ '^\h\w*$'
    echohl ErrorMsg | echo 'Only word characters that do not start with a digit are supported on <lhs>' | echohl NONE
    return
  endif
  if a:0 > 0
    let rhs = a:1
  else
    echohl ErrorMsg | echo 'No <rhs> specified for alias' | echohl NONE
    return
  endif
  if has_key(s:aliases, rhs) || exists('b:aliases') && has_key(b:aliases, rhs)
    echohl ErrorMsg | echo "Another alias can't be used as <rhs>" | echohl NONE
    return
  endif
  if a:0 > 1 && a:2 ==# "<buffer>"
    if ! exists('b:aliases')
      let b:aliases = {}
    endif
    let b:aliases[lhs] = rhs
  else
    let s:aliases[lhs] = rhs
  endif
endfunction

function! s:GetAlias(aliases, testValue)
  let aliasNames = keys(a:aliases)
  let aliasIdx = index(aliasNames, a:testValue)
  return (aliasIdx == -1 ? ['', ''] : [aliasNames[aliasIdx], a:aliases[aliasNames[aliasIdx]]])
endfunction

let s:singleRangeExpr = '\%(\d*\|[.$%]\|''\S\|\\[/?&]\|/.\{-}/\|?.\{-}?\)\%([+-]\d*\)\?'
let s:rangeExpr = s:singleRangeExpr.'\%([,;]'.s:singleRangeExpr.'\)\?'
" Commands are usually <Space>-delimited, but can also be directly followed by
" an argument (like :substitute, :ijump, etc.). According to :help E146, the
" delimiter can be almost any single-byte character. 
" Note: We use branches, not a (better performing?) single /[...]/ atom, because
" of the uncertainties of escaping these characters. 
function! s:IsCmdDelimiter(char)
    return (len(a:char) == 1 && a:char =~# '\p' && a:char !~# '[[:alpha:][:digit:]\\"|]')
endfunction
let s:cmdDelimiterExpr = '\V\%(' . 
\ join(
\   filter(
\     map(
\       range(0, 255),
\       'nr2char(v:val)'
\     ),
\     's:IsCmdDelimiter(v:val)'
\   ),
\   '\|'
\ ). '\)\m'
function! s:ExpandAlias()
  let partCmd = strpart(getcmdline(), 0, getcmdpos())

  " First just grab the command before the cursor. 
  let commandMatch = matchlist(partCmd, '\(\h\w*\)\(!\?\)\(' . s:cmdDelimiterExpr . '.*\|\)$')
  if commandMatch == []
    return ' '
  endif
  let [commandUnderCursor, aliasUnderCursor, commandBang, commandArgs] = commandMatch[0:3]

  " And test whether it is a command, or just appears somewhere else, e.g. as
  " part of an argument. 
  if partCmd !~# '\%(^\|\\\@<!|\)\s*\%('.s:cmdPrefixesExpr.'\)\?'.s:rangeExpr.'\s*' .
  \ '\V'.escape(commandUnderCursor, '\').'\$'
    return ' '
  endif

  " Then test whether it is aliased. 
  let alias = ''
  if exists('b:aliases')
    let [alias, expansion] = s:GetAlias(b:aliases, aliasUnderCursor)
  endif
  if empty(alias)
    let [alias, expansion] = s:GetAlias(s:aliases, aliasUnderCursor)
  endif
  if empty(alias)
    return ' '
  endif

  return repeat("\<BS>",
  \ len(split(commandUnderCursor, '\zs'))
  \) . expansion . commandBang . commandArgs . ' '
endfunction
" We only expand on <Space>, not on all non-alphanumeric characters that can
" delimit a command, because all the necessary :cmaps may interfere with other
" plugins' mappings. Instead, an argument that directly follows the command is
" handled inside s:ExpandAlias(). 
" Note: If :cnoremap is used, the mapping doesn't trigger expansion of :cabbrev
" any more. 
cmap <expr> <Space> getcmdtype() ==# ':' && ! &paste ? <SID>ExpandAlias() : ' '


function! s:OnCmdlineExit( exitKey )
  " Remove temporary hooks. 
  cunmap <CR>
  cunmap <Esc>
  cunmap <C-c>

  return a:exitKey
endfunction

cnoremap <expr> <SID>CR <SID>OnCmdlineExit("\<lt>CR>")
function! s:InstallCommandLineHook()
  " Despite :cmap, a remapped <CR> doesn't trigger expansion of :cabbrev any more. 
  " A <Space><BS> combo will do this for us, and also expand our aliases (via the
  " :cmap <Space> defined by this plugin). 
  "
  " Unfortunately, any :cmap'ped <CR> will also suppress the automatic opening
  " of the folds of a search result when doing a search via / and ?. (This is
  " due to Vim's internal rules about auto-opening folds, which get suppressed
  " whenever such a command is executed not directly by the user.) The only way
  " to work around this is to define the <CR> hook only temporarily whenever a
  " command-line of type "Ex command" is opened, so that there is no <CR> :cmap
  " in all other types of command-line mode. 

  " Expand Vim abbreviations and our own aliases also when submitting the
  " entered command-line. 
  " Avoid recursive <CR> mapping via intermediate :cnoremap <CR> mapping, and
  " remove the hooks inside that final mapping. 
  cmap <CR> <Space><BS><SID>CR

  " Remove hooks when command-line mode is aborted, too. 
  " Note: Must always use <C-c> to exit, <Esc> somehow doesn't work. 
  cnoremap <expr> <Esc> <SID>OnCmdlineExit("\<lt>C-c>")
  cnoremap <expr> <C-c> <SID>OnCmdlineExit("\<lt>C-c>")

  return ':'
endfunction
nnoremap <expr> : <SID>InstallCommandLineHook()


function! UnAlias(...)
  if a:0 == 0
    echohl ErrorMsg | echo "No aliases specified" | echohl NONE
    return
  endif

  let aliasesToRemove = copy(a:000)
  if exists('b:aliases')
    let aliases = filter(copy(aliasesToRemove), 'has_key(b:aliases, v:val)')
    if len(aliases) > 0
      call filter(b:aliases, 'index(aliases, v:key) == -1')
    endif
    call filter(aliasesToRemove, 'index(aliases, v:val) == -1')
  endif

  let aliases = filter(copy(aliasesToRemove), 'has_key(s:aliases, v:val)')
  if len(aliases) > 0
    call filter(s:aliases, 'index(aliases, v:key) == -1')
  endif
  if len(aliases) != len(aliasesToRemove)
    let badAliases = filter(copy(aliasesToRemove), 'index(aliases, v:val) == -1')
    echohl ErrorMsg | echo "No such aliases: " . join(badAliases, ' ') | echohl NONE
  endif
endfunction

function! s:FilterAliases(aliases, listPrefix, ...)
  if a:0 == 0
    let goodAliases = keys(a:aliases)
  else
    let goodAliases = filter(copy(a:000), 'has_key(a:aliases, v:val) != 0')
  endif
  if len(goodAliases) == 0
    return []
  else
    return map(copy(goodAliases), 'printf("%-8s\t%s%s", v:val, a:listPrefix, a:aliases[v:val])')
  endif
endfunction
function! s:Aliases(...)
  let goodAliases = []
  if exists('b:aliases')
    let goodAliases = call('s:FilterAliases', [b:aliases, '@'] + a:000)
  endif
  let goodAliases += call('s:FilterAliases', [s:aliases, ' '] + a:000)

  if len(goodAliases) > 0
    echo join(goodAliases, "\n")
  endif
endfunction

" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo

" vim6:fdm=marker sw=2
