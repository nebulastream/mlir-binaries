cd llvm-project
rm -rf ./build
mkdir build
cmake -G Ninja -S llvm -B build -DCMAKE_BUILD_TYPE=Release \
			        -DLLVM_ENABLE_PROJECTS="clang;lld;mlir"   \
-DBOOTSTRAP_LLVM_ENABLE_LTO=ON \
-DLLVM_INCLUDE_EXAMPLES=OFF    \
				-DLLVM_BUILD_EXAMPLES=OFF \
				-DLIBCXX_INCLUDE_BENCHMARKS=OFF \
				-DLLVM_OPTIMIZED_TABLEGEN=ON \
				-DLLVM_TARGETS_TO_BUILD="X86" \
                                -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind;compiler-rt" \
                                -DLLVM_RUNTIME_TARGETS="x86_64-unknown-linux-gnu"
ninja -C build runtimes
#ninja -C build check-runtimes


