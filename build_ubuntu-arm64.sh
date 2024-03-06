#!/bin/bash
# Copyright (C) 2020 by the NebulaStream project (https://nebula.stream)

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#    https://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

cd /build_dir/llvm-project
rm -rf ./build
mkdir build
cmake -G Ninja -S llvm -B build -DCMAKE_BUILD_TYPE=Release \
			    	-DLLVM_ENABLE_PROJECTS="mlir"   \
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


