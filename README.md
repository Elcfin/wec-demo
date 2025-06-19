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

### compile

```Bash
$  g++ -o file_demo file_demo.cc -lisal
```

### run

```Bash
$  ./file_demo -f /dev/shm
```

## part_chunk_demo

### compile

```Bash
$  g++ -o part_chunk_demo part_chunk_demo.cc -lisal
```
### run

```Bash
$  ./part_chunk_demo -v -o k64_m4_b32_s16_batch -t
```

## CPU

```Bash
$  lscpu
```

## IO

### write

```Bash
$  dd if=/dev/zero of=testfile bs=1M count=1024 oflag=direct
```

### read

```Bash
$  dd if=testfile of=/dev/null bs=1M count=1024 iflag=direct 
```