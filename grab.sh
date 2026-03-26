dest=bitstream
base=tb_dual_ltc2656

mkdir $dest 2>/dev/null

bit=project.runs/impl_1/top_level_wrapper.bit 
ltx=project.runs/impl_1/top_level_wrapper.ltx
bin=project.runs/impl_1/top_level_wrapper.bin

if [ ! -f $bit ]; then
    echo "${bit} doesn't appear to exist"
    exit 1
fi

rm -rf ${dest}/${base}.bit
rm -rf ${dest}/${base}.bin
rm -rf ${dest}/${base}.ltx

                cp $bit ${dest}/${base}.bit
test -f $bin && cp $bin ${dest}/${base}.bin 
test -f $ltx && cp $ltx ${dest}/${base}.ltx

