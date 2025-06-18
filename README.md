# README

## common

We can use  apt  to install the required tools.

● gcc & g++

● make

● nasm

● libtool & autoconf

● git

● ssh & openssh-server

```Bash
$  sudo apt update
$  sudo apt install gcc g++ make nasm autoconf libtool git ssh openssh-server
```

### ISA-L

```Bash
$  git clone https://github.com/intel/isa-l.git
$  cd isa-l
$  ./autogen.sh
$  ./configure; make; sudo make install
```

## file_demo

```Bash
$  g++ -o file_demo file_demo.cc -lisal
```

## part_chunk_demo

```Bash
$  g++ -o part_chunk_demo part_chunk_demo.cc -lisal
```