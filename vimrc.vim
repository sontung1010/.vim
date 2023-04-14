augroup HighlightTrailingSpaces
  autocmd!
  autocmd VimEnter,WinEnter,ColorScheme * highlight TrailingSpaces term=underline guibg=Red ctermbg=Red
  autocmd VimEnter,WinEnter, * match TrailingSpaces /\s\+$/
augroup END
execute pathogen#infect()
execute pathogen#helptags()
set nocompatible
syntax on
syntax enable
filetype on
set laststatus=2 " Always show the statusline "
set encoding=utf-8 " Necessary to show Unicode glyphs "
set rtp+=~/.vim/bundle/vundle
"call vundle#rc()

" let Vundle manage Vundle
" required!
"Bundle 'gmarik/vundle'



let g:syntastic_aggregate_errors = 1
let g:syntastic_auto_loc_list = 1
let g:netrw_liststyle = 6


call plug#begin()
  Plug 'ghifarit53/tokyonight-vim'
  Plug 'joshdick/onedark.vim'
  Plug 'sickill/vim-monokai'
  Plug 'fatih/vim-go', { 'do': ':GoInstallBinaries' }
  Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
  Plug 'junegunn/fzf.vim'
  Plug 'vim-ruby/vim-ruby'
  Plug 'yuezk/vim-js'
  Plug 'tpope/vim-surround'
  Plug 'maxmellon/vim-jsx-pretty'
  Plug 'jiangmiao/auto-pairs'
  Plug 'uiiaoo/java-syntax.vim'
  Plug 'vim-python/python-syntax'
  Plug 'itchyny/lightline.vim'
  Plug 'vim-python/python-syntax'
  Plug 'octol/vim-cpp-enhanced-highlight'
  Plug 'preservim/nerdcommenter'
  Plug 'preservim/nerdtree' |
            \ Plug 'Xuyuanp/nerdtree-git-plugin' |
            \ Plug 'ryanoasis/vim-devicons'
  Plug 'godlygeek/tabular'
  Plug 'wesQ3/vim-windowswap'
  Plug 'tpope/vim-fugitive'
  Plug 'farmergreg/vim-lastplace'
  Plug 'mhinz/vim-signify'
  Plug 'valloric/youcompleteme'
call plug#end()

" Start NERDTree. If a file is specified, move the cursor to its window.
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * NERDTree | if argc() > 0 || exists("s:std_in") | wincmd p | endif

" Start NERDTree and leave the cursor in it.
"autocmd VimEnter * NERDTree

let NERDTreeShowHidden = 1
" Exit Vim if NERDTree is the only window remaining in the only tab.
autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif


set termguicolors
let g:tokyonight_style = 'night' " available: night, storm
let g:tokyonight_enable_italic = 0
let g:tokyonight_disable_italic_comment = 1
let g:tokyonight_transparent_background = 1
let g:lightline = {'colorscheme' : 'tokyonight'}

let g:python_highlight_all = 1
let g:cpp_class_scope_highlight = 1
let g:cpp_member_variable_highlight = 1
let g:cpp_class_decl_highlight = 1
let g:cpp_posix_standard = 1
let g:cpp_experimental_simple_template_highlight = 1
let g:cpp_concepts_highlight = 1


let g:go_info_mode='gocode'
let g:terraform_align=1
filetype plugin indent on
set t_Co=256
set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab
set smarttab
set shiftround
set autoindent
set smartindent
set number
set cursorline!
set cursorcolumn
"set colorcolumn=80
set hlsearch
set noswapfile
set ttyfast
set lazyredraw
set backspace=indent,eol,start
set rtp+=$GOPATH/src/golang.org/x/lint/misc/vim
set noerrorbells
set incsearch
"set textwidth=80
"set formatoptions+=t
set wrap linebreak

colorscheme molokai
"molokai, onedark, monokai, tokyonight
highlight Comment ctermfg=Gray

command! -bang -nargs=* Find call fzf#vim#grep('rg --column --line-number --no-heading --fixed-strings --ignore-case --no-ignore --hidden --follow --glob "!.git/*" --color "always" '.shellescape(<q-args>), 1, <bang>0)
