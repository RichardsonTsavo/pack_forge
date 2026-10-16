# Pack Forge

Empacota a saída de `flutter build windows --release` em um único `.exe`
autoextrator que instala, atualiza ou desinstala a aplicação em
`C:\Program Files\<NomeDaAplicacao>\`.

## Como usar

1. Gere o launcher (necessário após clonar ou ao alterar `launcher/` ou `lib/core/`):

   ```
   dart run tool/build_launcher.dart
   ```

2. Rode ou gere o Pack Forge (`flutter run -d windows` ou `flutter build windows --release`).
3. Na interface, selecione a pasta da build, o executável principal, o nome da
   aplicação, o ícone (opcional) e o local de saída, e clique em **Gerar executável**.

## Estrutura

| Caminho | Função |
|---|---|
| `lib/core/` | Dart puro compartilhado: formato do pacote, validação de nomes/caminhos, edição de PE. |
| `lib/packer/` | Inspeção da build e geração do executável (roda em isolate). |
| `lib/ui/` | Interface Flutter do empacotador. |
| `launcher/` | Autoextrator (Dart AOT + Win32, sem Flutter). |
| `tool/build_launcher.dart` | Compila o launcher, aplica manifest e subsistema GUI e copia para `assets/launcher/`. |

## Formato do executável gerado

```
[launcher.exe + ícone][payload: arquivos deflate][manifest JSON][trailer 80 bytes]
```

O trailer guarda magic, versão, limites e SHA-256 do manifest. O manifest guarda
o SHA-256 de cada arquivo, conferido antes e depois da extração.

## Comportamento do instalador

- **Pasta não existe:** confirmação → UAC → extração numa pasta temporária
  `C:\Program Files\.pkforge.<id>.<aleatório>.new` → validação → renomeia para a
  pasta final → cria o atalho na área de trabalho → inicia a aplicação.
- **Pasta existe:** oferece Atualizar, Desinstalar ou Cancelar. Só prossegue se a
  pasta contiver o executável principal do pacote.
  - *Atualizar:* exige a aplicação fechada; extrai e valida a nova versão, troca
    as pastas e apaga a pasta antiga inteira. Se a troca falhar, a versão
    anterior é mantida.
  - *Desinstalar:* exige a aplicação fechada; remove a pasta de instalação e o
    atalho (somente se ele apontar para essa instalação).
- Somente as operações de arquivo rodam elevadas. Atalho e início da aplicação
  rodam com o usuário atual, sem privilégios de administrador.
- Pastas temporárias que sobrarem de uma execução interrompida são removidas (ou
  a versão anterior é restaurada) na próxima execução do instalador.

## Limitações conhecidas

- O executável não é assinado: o SmartScreen/Defender pode exibir avisos.
- Não inclui o runtime do Visual C++; a build selecionada deve conter tudo o que
  a aplicação precisa.
- Não há controle de versão: qualquer pacote com o mesmo nome substitui a instalação.
- Se o instalador for aberto "como administrador", a aplicação iniciada ao final
  também roda elevada.
- Dados gravados pela aplicação dentro da pasta de instalação são apagados na
  atualização e na desinstalação (dados em `%APPDATA%` não são tocados).
