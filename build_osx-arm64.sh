#!/bin/bash

cd ./llvm-project
rm -rf ./build
mkdir build
cmake -G Ninja -S llvm -B build -DCMAKE_BUILD_TYPE=Release \
				-DLLVM_ENABLE_PROJECTS="mlir"   \
				-DLLVM_ENABLE_ZLIB="OFF" \
				-DLLVM_ENABLE_ZSTD="OFF" \
				-DLLVM_INCLUDE_EXAMPLES=OFF    \
				-DLLVM_INCLUDE_TESTS=OFF \
				-DLLVM_INCLUDE_BENCHMARKS=OFF \
				-DLLVM_BUILD_EXAMPLES=OFF \
				-DLIBCXX_INCLUDE_BENCHMARKS=OFF \
				-DLLVM_OPTIMIZED_TABLEGEN=ON \
				-DCMAKE_INSTALL_PREFIX="../mlir" \
				-DLLVM_TARGETS_TO_BUILD="AArch64" \
				-DLLVM_BUILD_TOOLS=OFF \
				-DLLVM_ENABLE_TERMINFO=OFF \
				-DLLVM_ENABLE_Z3_SOLVER=OFF \
				-DCOMPILER_RT_ENABLE_IOS=OFF \
				-DCOMPILER_RT_ENABLE_WATCHOS=OFF \
				-DCOMPILER_RT_ENABLE_TVOS=OFF
ninja -C build 
#ninja -C build clang-format
#ninja -C build llvm-cov
ninja -C build runtimes
ninja -C build install
#ninja -C build install llvm-cov
ninja -C build mlir-libraries mlir-cmake-exports mlir-headers

#ninja -C build check-runtimes


