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
get_dep dbus https://github.com/zielmicha/nim-dbus 7906c123f81bbfec911140983e43a0f648a10b23 ''
get_dep libcommon https://github.com/networkosnet/libcommon d18d6ccdb4863f3f935a3b3c0b347206dea840bb ''
get_dep niceconf https://github.com/networkosnet/niceconf 6e9d7dc44a8d2bb30338b92844ee2f620590a375 ''
get_dep reactor https://github.com/zielmicha/reactor.nim e1838c1d6d1091661f4be401cc8573ac485d54bd ''

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
