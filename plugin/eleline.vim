"=============================================================================
" Filename: eleline.vim
" Author: Liu-Cheng Xu
" Fork: Rocky (@yanzhang0219)
" URL: https://github.com/yanzhang0219/eleline.vim
" License: MIT License
" =============================================================================

" Customization: To add an item
" 1. first write a function to return what you want to display on the status bar
" 2. create a highlight group for it to color it, see HiStatusline() below
" 3. add it to the status line, see StatusLine() below

" TODO: Adapt for the light themes

scriptencoding utf-8
if exists('g:loaded_eleline') || v:version < 700
  finish
endif

let g:loaded_eleline = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:font = get(g:, 'eleline_powerline_fonts', 0)
let s:gui = has('gui_running')
let s:is_win = has('win32')
let s:git_branch_cmd = add(s:is_win ? ['cmd', '/c'] : ['bash', '-c'], 'git branch')

" Icons here can be customized
if s:font
  let s:fn_icon = ''
  let s:git_branch_symbol = ''
  let s:git_branch_star_substituted = ''
  let s:logo = ''
  let s:diff_icons = [' ', '柳', ' ']
  let s:separator = '⏽'
else
  let s:fn_icon = ''
  let s:git_branch_symbol = 'Git:'
  let s:git_branch_star_substituted = 'Git:'
  let s:logo = '|'
  let s:diff_icons = ['+', '~', '-']
  let s:separator = '|'
endif

let s:jobs = {}

function! ElelineBufnrWinnr() abort
  return '  W:' . winnr() . ' ' . s:logo . ' B:' . bufnr('%') . ' '
endfunction

function! ElelineTotalBuf() abort
  return '[' . len(filter(range(1, bufnr('$')), 'buflisted(v:val)')) . ']'
endfunction

function! ElelinePaste() abort
  return &paste ? 'PASTE ' : ''
endfunction

function! ElelineFileSize(f) abort
  let l:size = getfsize(expand(a:f))
  if l:size == 0 || l:size == -1 || l:size == -2
    return ''
  endif
  if l:size < 1024
    let size = l:size . ' B'
  elseif l:size < 1024 * 1024
    let size = printf('%.1f', l:size/1024.0) . 'K'
  elseif l:size < 1024 * 1024 * 1024
    let size = printf('%.1f', l:size/1024.0/1024.0) . 'M'
  else
    let size = printf('%.1f', l:size/1024.0/1024.0/1024.0) . 'G'
  endif
  return ' ' . size . ' '
endfunction

function! ElelineCurFname() abort
  return &filetype ==# 'startify' ? ' ' : '  ' . expand('%:p:t') . ' '
endfunction

function! ElelineError() abort
  if exists('g:loaded_ale')
    let s:ale_counts = ale#statusline#Count(bufnr(''))
    return s:ale_counts[0] == 0 ? '' : '•' . s:ale_counts[0] . ' '
  endif
  return ''
endfunction

function! ElelineWarning() abort
  if exists('g:loaded_ale')
    " Ensure ElelineWarning() is called after ElelineError() so that s:ale_counts can be reused.
    return s:ale_counts[1] == 0 ? '' : '•' . s:ale_counts[1] . ' '
  endif
  return ''
endfunction

function! ElelineTag() abort
  return exists("b:gutentags_files") ? '  ' . gutentags#statusline() . ' ' : ''
endfunction

function! s:IsTmpFile() abort
  return !empty(&buftype)
        \ || index(['startify', 'gitcommit', 'defx', 'vista', 'vista_kind'], &filetype) > -1
        \ || expand('%:p') =~# '^/tmp'
endfunction

" Reference: https://github.com/chemzqm/vimrc/blob/master/statusline.vim
function! ElelineGitBranch(...) abort
  if s:IsTmpFile()
    return ''
  endif
  let reload = get(a:, 1, 0) == 1
  if exists('b:eleline_branch') && !reload
    return b:eleline_branch
  endif
  if !exists('*FugitiveExtractGitDir')
    return ''
  endif
  let dir = exists('b:git_dir') ? b:git_dir : FugitiveExtractGitDir(resolve(expand('%:p')))
  if empty(dir)
    return ''
  endif
  let b:git_dir = dir
  let roots = values(s:jobs)
  let root = fnamemodify(dir, ':h')
  if index(roots, root) >= 0
    return ''
  endif

  if exists('*job_start')
    let job = job_start(s:git_branch_cmd, {'out_io': 'pipe', 'err_io':'null',  'out_cb': function('s:OutHandler')})
    if job_status(job) ==# 'fail'
      return ''
    endif
    let s:cwd = root
    let job_id = ch_info(job_getchannel(job))['id']
    let s:jobs[job_id] = root
  elseif exists('*jobstart')
    let job_id = jobstart(s:git_branch_cmd, {
          \ 'cwd': root,
          \ 'stdout_buffered': v:true,
          \ 'stderr_buffered': v:true,
          \ 'on_exit': function('s:ExitHandler')
          \})
    if job_id == 0 || job_id == -1
      return ''
    endif
    let s:jobs[job_id] = root
  elseif exists('g:loaded_fugitive')
    let l:head = fugitive#head()
    return empty(l:head) ? '' : '  ' . s:git_branch_symbol . ' ' . l:head . ' '
  endif

  return ''
endfunction

function! s:OutHandler(channel, message) abort
  if a:message =~# '^* '
    let l:job_id = ch_info(a:channel)['id']
    if !has_key(s:jobs, l:job_id)
      return
    endif
    let l:branch = substitute(a:message, '*', '  ' . s:git_branch_star_substituted, '')
    call s:SetGitBranch(s:cwd, l:branch . ' ')
    call remove(s:jobs, l:job_id)
  endif
endfunction

function! s:ExitHandler(job_id, data, _event) dict abort
  if !has_key(s:jobs, a:job_id) || !has_key(self, 'stdout')
    return
  endif
  if v:dying
    return
  endif
  let l:cur_branch = join(filter(self.stdout, 'v:val =~# "*"'))
  if !empty(l:cur_branch)
    let l:branch = substitute(l:cur_branch, '*', '  ' . s:git_branch_star_substituted, '')
    call s:SetGitBranch(self.cwd, l:branch . ' ')
  else
    let err = join(self.stderr)
    if !empty(err)
      echoerr err
    endif
  endif
  call remove(s:jobs, a:job_id)
endfunction

function! s:SetGitBranch(root, str) abort
  let buf_list = filter(range(1, bufnr('$')), 'bufexists(v:val)')
  let root = s:is_win ? substitute(a:root, '\', '/', 'g') : a:root
  for nr in buf_list
    let path = fnamemodify(bufname(nr), ':p')
    if s:is_win
      let path = substitute(path, '\', '/', 'g')
    endif
    if match(path, root) >= 0
      call setbufvar(nr, 'eleline_branch', a:str)
    endif
  endfor
  redraws!
endfunction

function! ElelineGitStatus() abort
  if exists('b:sy.stats')
    let l:summary = b:sy.stats
  elseif exists('b:gitgutter.summary')
    let l:summary = b:gitgutter.summary
  else
    let l:summary = [0, 0, 0]
  endif
  if max(l:summary) > 0
    return '  ' . s:diff_icons[0] . l:summary[0] . ' ' . s:diff_icons[1] . l:summary[1] . ' ' . s:diff_icons[2] . l:summary[2] . ' '
  elseif !empty(get(b:, 'coc_git_status', ''))
    return ' ' . b:coc_git_status . ' '
  endif
  return ''
endfunction

function! ElelineLCN() abort
  if !exists('g:LanguageClient_loaded')
    return ''
  endif
  return eleline#LanguageClientNeovim()
endfunction

function! ElelineVista() abort
  return !empty(get(b:, 'vista_nearest_method_or_function', '')) ? '  ' . s:fn_icon . ' ' . b:vista_nearest_method_or_function : ''
endfunction

function! ElelineNvimLsp() abort
  if s:IsTmpFile()
    return ''
  endif
  if luaeval('#vim.lsp.buf_get_clients() > 0')
    let l:lsp_status = luaeval("require('lsp-status').status()")
    return empty(l:lsp_status) ? '' : '  ' . s:fn_icon . ' ' . l:lsp_status
  endif
  return ''
endfunction

function! ElelineCoc() abort
  if s:IsTmpFile()
    return ''
  endif
  if get(g:, 'coc_enabled', 0)
    return coc#status() . ' '
  endif
  return ''
endfunction

function! ElelineVimMode() abort
  let status = {"n": "🅽  ", "V": "🆅  ", "v": "🆅  ", "\<C-v>": "🆅  ", "i": "🅸  ", "R": "🆁  ", "r": "🆁  ", "s": "🆂  ", "t": "🆃  ", "c": "🅲  ", "!": "SE "}
  let l:mode = mode()
  call s:ChangeModeBg(l:mode)
  return '  ' . status[l:mode]
endfunction

let s:mode = ''
function! s:ChangeModeBg(curmode)
  if s:mode ==# a:curmode
    return
  endif
  let s:mode = a:curmode

  if a:curmode ==# 'i'
    call s:HiModeBg(149)
  elseif a:curmode ==# 'c'
    call s:HiModeBg(208)
  elseif a:curmode =~? '\|v'
    call s:HiModeBg(32)
  elseif a:curmode ==# 't'
    call s:HiModeBg(184)
  elseif a:curmode ==# 'R'
    call s:HiModeBg(197)
  else
    call s:HiModeBg(140)
  endif
endfunction

function! s:HiModeBg(bg) abort
  execute printf('hi ElelineVimMode ctermbg=%d guibg=%s', a:bg, s:colors[a:bg])
endfunction

function! ElelineScrollbar() abort
  let l:scrollbar_chars = [
        \  '▁', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'
        \  ]

  let l:current_line = line('.') - 1
  let l:total_lines = line('$') - 1

  if l:current_line == 0
    let l:index = 0
  elseif l:current_line == l:total_lines
    let l:index = -1
  else
    let l:line_no_fraction = floor(l:current_line) / floor(l:total_lines)
    let l:index = float2nr(l:line_no_fraction * len(l:scrollbar_chars))
  endif

  return l:scrollbar_chars[l:index]
endfunction

function! ElelineDevicon() abort
  let l:icon = ''
  if exists("*WebDevIconsGetFileTypeSymbol")
    let l:icon = substitute(WebDevIconsGetFileTypeSymbol(), "\u00A0", '', '')
  else
    let l:file_name = expand("%:t")
    let l:file_extension = expand("%:e")
    if luaeval("require('nvim-web-devicons').get_icon")(l:file_name,l:file_extension) == v:null
      let l:icon = ''
    else
      let l:icon = luaeval("require('nvim-web-devicons').get_icon")(l:file_name,l:file_extension)
    endif
  endif
  return '  ' . l:icon
endfunction

function! s:DefStatuslineItem(fn) abort
  return printf('%%#%s#%%{%s()}%%*', a:fn, a:fn)
endfunction

function! s:StatusLine() abort

  " Item candidates for the left section
  let l:mode = s:DefStatuslineItem('ElelineVimMode')
  let l:bufnr_winnr = s:DefStatuslineItem('ElelineBufnrWinnr')
  let l:paste = s:DefStatuslineItem('ElelinePaste')
  let l:tot = s:DefStatuslineItem('ElelineTotalBuf')
  let l:devicon = s:font ? s:DefStatuslineItem('ElelineDevicon') : ''
  let l:curfname = s:DefStatuslineItem('ElelineCurFname')
  let l:branch = s:DefStatuslineItem('ElelineGitBranch')
  let l:status = s:DefStatuslineItem('ElelineGitStatus')
  " let l:error = s:DefStatuslineItem('ElelineError')
  " let l:warning = s:DefStatuslineItem('ElelineWarning')
  let l:tags = s:DefStatuslineItem('ElelineTag')
  " let l:lcn = s:DefStatuslineItem('ElelineLCN')
  let l:coc = s:DefStatuslineItem('ElelineCoc')
  " let l:lsp = s:DefStatuslineItem('ElelineNvimLsp')
  let l:vista = s:DefStatuslineItem('ElelineVista')

  " Item candidates for the right section
  let l:m_r_f = '%#ElelineFileType# %m%r%y %*'
  let l:enc = '%#ElelineFileFmtEnc# %{&fenc != "" ? &fenc : &enc} ' . s:separator . ' %{&bomb ? ",BOM " : ""}'
  let l:ff = '%{&ff} %*'
  let l:pos = '%#ElelinePosPct# %l/%L:%c%V ' . s:separator
  let l:scroll = s:font ? s:DefStatuslineItem('ElelineScrollbar') : ''
  let l:pct = ' %P ' . l:scroll . '%#ElelinePosPct# %*'
  let l:fsize = '%#ElelineFileSize#%{ElelineFileSize(@%)}%*'

  " Assemble the items you need
  let l:prefix = l:mode . l:bufnr_winnr . l:paste
  let l:common = l:devicon . l:curfname . l:branch . l:status . l:tags . l:coc . l:vista
  if get(g:, 'eleline_slim', 0)
    return l:prefix . '%<' . l:common
  endif
  let l:right = l:m_r_f . l:enc . l:ff . l:pos . l:pct . l:fsize

  return l:prefix . l:tot . '%<' . l:common .'%=' . l:right
endfunction

" Colors here can be customized
let s:colors = {
      \   140 : '#af87d7', 149 : '#99cc66', 160 : '#d70000',
      \   171 : '#d75fd7', 178 : '#ffbb7d', 184 : '#ffe920',
      \   208 : '#ff8700', 232 : '#333300', 197 : '#cc0033',
      \   214 : '#ffff66', 124 : '#af3a03', 172 : '#b57614',
      \   32  : '#3a81c3', 89  : '#6c3163',
      \
      \   235 : '#262626', 236 : '#303030', 237 : '#3a3a3a',
      \   238 : '#444444', 239 : '#4e4e4e', 240 : '#585858',
      \   241 : '#606060', 242 : '#666666', 243 : '#767676',
      \   244 : '#808080', 245 : '#8a8a8a', 246 : '#949494',
      \   247 : '#9e9e9e', 248 : '#a8a8a8', 249 : '#b2b2b2',
      \   250 : '#bcbcbc', 251 : '#c6c6c6', 252 : '#d0d0d0',
      \   253 : '#dadada', 254 : '#e4e4e4', 255 : '#eeeeee',
      \ }

function! s:Extract(group, what, ...) abort
  if a:0 == 1
    return synIDattr(synIDtrans(hlID(a:group)), a:what, a:1)
  else
    return synIDattr(synIDtrans(hlID(a:group)), a:what)
  endif
endfunction

if !exists('g:eleline_background')
  let s:normal_bg = s:Extract('Normal', 'bg', 'cterm')
  if s:normal_bg >= 233 && s:normal_bg <= 243
    let s:bg = s:normal_bg
  else
    let s:bg = 235
  endif
else
  let s:bg = g:eleline_background
endif

" Don't change in gui mode
if has('termguicolors') && &termguicolors
  let s:bg = 235
endif

" TODO: Adapt for the light themes
" @light here is just a placeholder
function! s:Hi(group, dark, light, ...) abort
  let [fg, bg] = a:dark
  execute printf('hi %s ctermfg=%d guifg=%s ctermbg=%d guibg=%s',
        \ a:group, fg, s:colors[fg], bg, s:colors[bg])
  if a:0 == 1
    execute printf('hi %s cterm=%s gui=%s', a:group, a:1, a:1)
  endif
endfunction

" Create highlight group for each item
function! s:HiStatusline() abort

  " Left section
  call s:Hi('ElelineVimMode'    , [232 , 140]    , ['' , '']    , 'bold')
  call s:Hi('ElelineBufnrWinnr' , [232 , 178]    , ['' , ''])
  call s:Hi('ElelineTotalBuf'   , [178 , s:bg+8] , ['' , ''])
  call s:Hi('ElelinePaste'      , [232 , 178]    , ['' , '']    , 'bold')
  call s:Hi('ElelineDevicon'    , [171 , s:bg+4] , ['' , ''])
  call s:Hi('ElelineCurFname'   , [171 , s:bg+4] , ['' , '']    , 'bold')
  call s:Hi('ElelineGitBranch'  , [184 , s:bg+2] , ['' , '']    , 'bold')
  call s:Hi('ElelineGitStatus'  , [208 , s:bg+2] , ['' , ''])
  " call s:Hi('ElelineError'      , [197 , s:bg+2] , ['' , ''])
  " call s:Hi('ElelineWarning'    , [214 , s:bg+2] , ['' , ''])
  call s:Hi('ElelineTag'        , [149 , s:bg+2] , ['' , ''])
  " call s:Hi('ElelineLCN'        , [197 , s:bg+2] , ['' , ''])
  call s:Hi('ElelineCoc'        , [197 , s:bg+2] , ['' , ''])
  " call s:Hi('ElelineNvimLsp'    , [197 , s:bg+2] , ['' , ''])
  call s:Hi('ElelineVista'      , [149 , s:bg+2] , ['' , ''])

  " Right section
  call s:Hi('ElelineFileType'   , [249 , s:bg+3] , ['' , ''])
  call s:Hi('ElelineFileFmtEnc' , [250 , s:bg+4] , ['' , ''])
  call s:Hi('ElelinePosPct'     , [251 , s:bg+5] , ['' , ''])
  call s:Hi('ElelineScrollbar'  , [178 , 140]    , ['' , ''])
  call s:Hi('ElelineFileSize'   , [252 , s:bg+6] , ['' , ''])

  call s:Hi('StatusLine'        , [140 , s:bg+2] , ['' , '']    , 'none')
endfunction

function! s:SetQuickFixStatusline() abort
  let l:bufnr_winnr = s:DefStatuslineItem('ElelineBufnrWinnr')
  let &l:statusline = l:bufnr_winnr . "%{exists('w:quickfix_title')? ' '.w:quickfix_title : ''} %l/%L %p"
endfunction

" Note that the "%!" expression is evaluated in the context of the
" current window and buffer, while %{} items are evaluated in the
" context of the window that the statusline belongs to.
function! s:SetStatusline(...) abort
  call ElelineGitBranch(1)
  let &l:statusline = s:StatusLine()
  " User-defined highlightings shoule be put after colorscheme command.
  call s:HiStatusline()
endfunction

if exists('*timer_start')
  call timer_start(100, function('s:SetStatusline'))
else
  call s:SetStatusline()
endif

augroup eleline
  autocmd!
  autocmd User GitGutter,Startified,LanguageClientStarted call s:SetStatusline()
  autocmd BufWinEnter,ShellCmdPost,BufWritePost * call s:SetStatusline()
  autocmd FileChangedShellPost,ColorScheme * call s:SetStatusline()
  autocmd FileReadPre,ShellCmdPost,FileWritePost * call s:SetStatusline()
  autocmd FileType qf call s:SetQuickFixStatusline()
augroup END

let &cpoptions = s:save_cpo
unlet s:save_cpo
