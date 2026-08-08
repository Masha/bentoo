# bentoo

Overlay Gentoo que serve de base a um **projeto de sistema operacional**.

## Princípio norteador

**O bentoo é uma distribuição, não uma máquina.** O mantenedor (`lucascouts`) é
apenas quem empacota — não é o público-alvo.

Consequências práticas, válidas para toda decisão de empacotamento:

- **Nunca dimensione um pacote pelo hardware do mantenedor.** O hardware dele é
  irrelevante para a decisão de portar, para as USE flags expostas e para os
  defaults escolhidos.
- **Cubra hardware de terceiros por padrão:** NVIDIA (incluindo gerações
  legadas), AMD (ROCm/Vulkan), Intel (SYCL/oneAPI), NPUs (XDNA2 e afins),
  CPU-only e ARM64 — não só x86_64 com GPU discreta.
- **Cubra casos de uso de terceiros:** desktop, workstation, servidor,
  headless, container, edge.
- Backends de aceleração vão como **USE flags opcionais**, nunca hardcoded.
  Ninguém deve ser forçado a puxar CUDA para usar um pacote em CPU.
- `KEYWORDS` deve incluir `~arm64` sempre que o upstream suportar; restringir a
  `~amd64` é uma decisão que precisa de justificativa, não um default.
- "Não serve para mim" **não é** critério de exclusão. "Upstream abandonado",
  "não compila", "sem licença clara" são.

## Convenções do overlay

- `thin-manifests = true`
- Autoupdate configurado em `.autoupdate/packages.toml`
- Pacote removido do overlay vira `enabled = false` no `packages.toml`; nunca
  se apaga a entrada (preserva o probe já verificado)
- Todo pacote que instala uma unit systemd instala também um init script
  OpenRC do mesmo escopo — sistema em `/etc/init.d`, usuário em
  `/etc/user/init.d`; a assimetria é deliberada: a unit é gateada por
  `USE=systemd`, o init script **nunca** é, porque ele não custa nada a quem
  usa systemd e é a única forma de rodar o daemon para quem não usa. Decorre
  de "cubra casos de uso de terceiros" acima: um serviço systemd-only é o init
  system do mantenedor confundido com o do público. Conferido por
  `scripts/check-openrc-coverage.sh`, que classifica o overlay inteiro e sai 1
  ao achar lacuna
