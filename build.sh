#!/bin/sh
set -e
cd "$(dirname "$0")"

if [ -e nimenv.local ]; then
  echo 'nimenv.local exists. You may use `nimenv build` instead of this script.'
  #exit 1
fi

mkdir -p .nimenv/nim
mkdir -p .nimenv/deps

NIMHASH=8f8d38d70ed57164795fc55e19de4c11488fcd31dbe42094e44a92a23e3f5e92
if ! [ -e .nimenv/nimhash -a \( "$(cat .nimenv/nimhash)" = "$NIMHASH" \) ]; then
  echo "Downloading Nim http://nim-lang.org/download/nim-0.14.2.tar.xz (sha256: $NIMHASH)"
  wget http://nim-lang.org/download/nim-0.14.2.tar.xz -O .nimenv/nim.tar.xz
  if ! [ "$(sha256sum < .nimenv/nim.tar.xz)" = "$NIMHASH  -" ]; then
    echo "verification failed"
    exit 1
  fi
  echo "Unpacking Nim..."
  rm -r .nimenv/nim
  mkdir -p .nimenv/nim
  cd .nimenv/nim
  tar xJf ../nim.tar.xz
  mv nim-*/* .
  echo "Building Nim..."
  make -j$(getconf _NPROCESSORS_ONLN)
  cd ../..
  echo $NIMHASH > .nimenv/nimhash
fi

get_dep() {
  set -e
  cd .nimenv/deps
  name="$1"
  url="$2"
  hash="$3"
  srcpath="$4"
  new=0
  if ! [ -e "$name" ]; then
    git clone --recursive "$url" "$name"
    new=1
  fi
  if ! [ "$(cd "$name" && git rev-parse HEAD)" = "$hash" -a $new -eq 0 ]; then
     cd "$name"
     git fetch --all
     git checkout -q "$hash"
     git submodule update --init
     cd ..
  fi
  cd ../..
  echo "path: \".nimenv/deps/$name$srcpath\"" >> nim.cfg
}

echo "path: \".\"" > nim.cfg

get_dep collections https://github.com/zielmicha/collections.nim 76fc5e7500adf814d500a0c8261aafba5928a692 ''
get_dep dbus https://github.com/zielmicha/nim-dbus b72f76b8033622e4a464bed26b69657e53859c94 ''
get_dep libcommon https://github.com/networkosnet/libcommon 1db0dea4c847300670aca3ba272b5c3a035759dc ''
get_dep niceconf https://github.com/networkosnet/niceconf 99bba9420dd8b1af31af453c5c15133c04a773d5 ''
get_dep reactor https://github.com/zielmicha/reactor.nim 99944d035adae1cb3728298d15486d14a09e51fc ''

echo '# reactor.nim requires pthreads
threads: "on"

# enable debugging
passC: "-g"
passL: "-g"

verbosity: "0"
hint[ConvFromXtoItselfNotNeeded]: "off"
hint[XDeclaredButNotUsed]: "off"

debugger: "native"

@if release:
  gcc.options.always = "-w -fno-strict-overflow -flto"
  gcc.cpp.options.always = "-w -fno-strict-overflow -flto"
  clang.options.always = "-w -fno-strict-overflow -flto"
  clang.cpp.options.always = "-w -fno-strict-overflow -flto"
  obj_checks: on
  field_checks: on
  bound_checks: on
@end' >> nim.cfg

mkdir -p bin
ln -sf ../.nimenv/nim/bin/nim bin/nim

echo "building netd"; bin/nim c -d:release --out:"$PWD/bin/netd" netd.nim
