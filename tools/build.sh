source /root/.profile
docker load --input $(nix-build --cores 4 ../default.nix --show-trace | grep tar)

