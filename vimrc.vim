" ~/.vimrc -> ~/.vim/vimrc.vim
" Skip everything on vim-tiny/vim-small (no +eval), e.g. the stock `vi`.
if !1 | finish | endif

set nocompatible
set encoding=utf-8

" ---------------------------------------------------------------- plugins
" Plugins live in ~/.vim/plugged (gitignored). Install with :PlugInstall,
" or ship them offline with ./bundle.sh. Missing plugins are simply skipped.
call plug#begin('~/.vim/plugged')
  " colorschemes (molokai itself is in ~/.vim/colors)
  Plug 'ghifarit53/tokyonight-vim'          " also provides the lightline theme
  " search
  Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
  Plug 'junegunn/fzf.vim'
  " syntax (ruby/java: vim's built-in runtime files are up to date)
  Plug 'yuezk/vim-js'
  Plug 'maxmellon/vim-jsx-pretty'
  Plug 'vim-python/python-syntax'
  Plug 'octol/vim-cpp-enhanced-highlight'
  Plug 'vhda/verilog_systemverilog.vim'
  " editing
  Plug 'tpope/vim-surround'
  Plug 'jiangmiao/auto-pairs'
  Plug 'preservim/nerdcommenter'
  Plug 'godlygeek/tabular'
  Plug 'wesQ3/vim-windowswap'
  " ui / git
  Plug 'itchyny/lightline.vim'
  Plug 'tpope/vim-fugitive'
  Plug 'mhinz/vim-signify'
  Plug 'farmergreg/vim-lastplace'
call plug#end()   " also runs: filetype plugin indent on | syntax enable

" ---------------------------------------------------------------- plugin options
let g:tokyonight_style = 'night'          " night, storm
let g:tokyonight_enable_italic = 0
let g:tokyonight_disable_italic_comment = 1
let g:tokyonight_transparent_background = 0
let g:lightline = {'colorscheme': 'tokyonight'}

let g:python_highlight_all = 1
let g:cpp_class_scope_highlight = 1
let g:cpp_member_variable_highlight = 1
let g:cpp_class_decl_highlight = 1
let g:cpp_posix_standard = 1
let g:cpp_experimental_simple_template_highlight = 1
let g:cpp_concepts_highlight = 1

let g:netrw_liststyle = 6
let g:netrw_dirhistmax = 0                " do not write ~/.vim/.netrwhist

" ---------------------------------------------------------------- editor
set laststatus=2
set tabstop=2 shiftwidth=2 softtabstop=2 expandtab smarttab shiftround
set autoindent smartindent
set number
set cursorline cursorcolumn
set hlsearch incsearch
set noswapfile
set ttyfast lazyredraw
set backspace=indent,eol,start
set noerrorbells
set wrap linebreak
set completeopt-=preview

" ---------------------------------------------------------------- colors
" True color everywhere except the bare Linux console.
if has('termguicolors') && $TERM !=# 'linux'
  set termguicolors
endif
silent! colorscheme molokai               " molokai, tokyonight
highlight Comment ctermfg=Gray

augroup HighlightTrailingSpaces
  autocmd!
  autocmd VimEnter,WinEnter,ColorScheme * highlight TrailingSpaces term=underline guibg=Red ctermbg=Red
  autocmd VimEnter,WinEnter * match TrailingSpaces /\s\+$/
augroup END

" ---------------------------------------------------------------- commands
" :Find <text>  -> ripgrep through fzf (needs `rg`)
command! -bang -nargs=* Find call fzf#vim#grep('rg --column --line-number --no-heading --fixed-strings --ignore-case --no-ignore --hidden --follow --glob "!.git/*" --color "always" '.shellescape(<q-args>), 1, <bang>0)
