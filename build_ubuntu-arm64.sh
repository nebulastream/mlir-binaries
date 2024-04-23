#!/bin/bash

cd /build_dir/llvm-project
rm -rf ./build
mkdir build
cmake -G Ninja -S llvm -B build -DCMAKE_BUILD_TYPE=DEBUG \
			    -DLLVM_ENABLE_PROJECTS="mlir,llvm"   \
				-DBOOTSTRAP_LLVM_ENABLE_LTO=OFF \
				-DLLVM_INCLUDE_EXAMPLES=OFF    \
				-DLLVM_INCLUDE_TESTS=OFF \
				-DLLVM_INCLUDE_BENCHMARKS=OFF \
				-DLLVM_BUILD_EXAMPLES=OFF \
				-DLIBCXX_INCLUDE_BENCHMARKS=OFF \
				-DLLVM_OPTIMIZED_TABLEGEN=ON \
				-DCMAKE_INSTALL_PREFIX="/build_dir/mlir" \
				-DLLVM_TARGETS_TO_BUILD="AArch64" \
				-DLLVM_BUILD_TOOLS=OFF \
				-DLLVM_ENABLE_ZSTD=OFF \
				-DLLVM_ENABLE_ZLIB="OFF" \
				-DLLVM_ENABLE_TERMINFO=OFF \
				-DLLVM_ENABLE_Z3_SOLVER=OFF 

ninja -j4 -C build 
#ninja -j4 -C build clang-format
#ninja -j4 -C build llvm-cov
ninja -j4 -C build runtimes
ninja -j4 -C build install
#ninja -j4 -C build install llvm-cov
#ninja -C build mlir-libraries mlir-cmake-exports mlir-headers

# remove stuff from build
rm -rf /build/utils
rm -rf /build/unittests
rm -rf /build/tools
rm -rf /build/third-party
rm -rf /build/test
rm -rf /build/runtimes
rm -rf /build/projects
rm -rf /build/CMakeFiles
rm -rf /build/benchmarks
#ninja -C build check-runtimes


