# disk-cleanup

Gerenciador de espaço em disco para Linux. Mostra o estado do disco, aponta o que mais ocupa espaço, avisa quando o espaço está baixo e apaga com segurança o que é descartável: caches de ferramentas e navegadores, pastas de build, lixeira, arquivos grandes e sobras do Docker.

Página e downloads: https://uesleinasch.github.io/disk-cleanup/

## O que ele faz

- **Visão geral** com espaço livre, alerta de espaço (atenção abaixo de 15% ou 20 GB; crítico abaixo de 5% ou 5 GB) e os maiores consumidores.
- **Diretórios mapeados**, com o crescimento desde a semana anterior.
- **Arquivos grandes** acima de 1 GB, com filtros, envio para a lixeira (com Desfazer) ou exclusão permanente.
- **Limpeza** de lixeira, caches (uv, pip, npm, yarn, pnpm, Gradle, NuGet, Cargo, navegadores, Playwright…) e builds (`node_modules`, `target`, `.stack-work`, `dist-newstyle`, `build`, `.dart_tool`, `bin`/`obj`…). Uma pasta de build só é reconhecida quando o arquivo de projeto está ao lado.
- **Docker**: build cache, containers parados, imagens e volumes sem uso.
- Toda exclusão abre um diálogo com o risco, o que some e quanto espaço volta. O que exige root (logs do journal, cache do apt, revisões antigas de snap) pede a senha uma única vez por lote, via `pkexec`.
- **Backup** para um disco externo:
  - as pastas que você escolher, sem dependências, caches e builds (`dist`, `build`, `bin`, `target` e `out` só saem quando o git diz que são ignorados, então um `vendor/bin` versionado fica);
  - os perfis do Brave, Chrome e Chromium, sem cache (navegador aberto é pulado, com "Tentar de novo");
  - chaves e configurações (SSH, git, GnuPG, keyring) num arquivo criptografado com AES256. A senha é pedida pela janela do sistema e não passa pelo app;
  - um `LEIA-ME-RESTAURAR.md` no disco com os comandos para restaurar tudo.

  O backup só acumula: nada é apagado dele, a não ser com a opção "Espelhar". A Visão geral lembra quando o último backup ficou antigo (7 dias, configurável).

## Instalação

1. Baixe o `disk-cleanup-<versão>-x86_64.AppImage` na [página de versões](https://github.com/uesleinasch/disk-cleanup/releases).
2. `chmod +x disk-cleanup-*.AppImage`
3. Execute o arquivo.

Requisitos: Ubuntu 22.04 ou mais novo (x86_64). O AppImage usa FUSE 2; se faltar, instale `libfuse2` ou rode com `--appimage-extract-and-run`. O backup usa `rsync` e, para as chaves, `gnupg` com um pinentry gráfico (`pinentry-gnome3`). O disco de destino precisa guardar permissões Unix (ext4, btrfs, xfs…); exFAT, NTFS e FAT32 não servem.

Os tamanhos aparecem em GB decimais (1 GB = 1.000.000.000 bytes). O `df -h` mostra GiB, por isso os números diferem um pouco.

## Desenvolvimento

```bash
flutter run -d linux
flutter test
packaging/appimage/build_appimage.sh 0.1.0-dev
```

Documentação de design em `docs/`.

## Licença

MIT
