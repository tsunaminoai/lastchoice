#!/bin/bash
targets=('x86_64' 'arm' 'aarch64' 'i386' 'riscv64')
OSes=('linux' 'macos' 'windows' 'freebsd')

echo > build.log
successes=0
failures=0
if [ ! -d "dist" ]; then
    mkdir dist
else
    rm -rf dist/*
fi

# Build for all targets
for target in ${targets[@]}; do
    for os in ${OSes[@]}; do
        rm -rf zig-out zig-cache
    
        echo -en "\x1b[30mBuilding for ${target}-${os} ... \x1b[0m" | tee -a build.log
        zig build \
            -Dtarget=${target}-${os} \
            -Doptimize=ReleaseSafe >> build.log 2>&1
        if [ $? == 0 ]; then
            echo -e "\x1b[32msucceeded\x1b[0m"
            successes=$((successes+1))
            zip -r "dist/lastchoice-${target}-${os}.zip" zig-out >> build.log 2>&1
        else
            echo -e "\x1b[31mfailed\x1b[0m"
            failures=$((failures+1))
        fi
    done
done

echo
echo "Builds succeeded: ${successes}"
echo "Builds failed: ${failures}"
echo
if [ $failures -gt 0 ]; then
    echo "check build.log for details"
    exit 1
fi

