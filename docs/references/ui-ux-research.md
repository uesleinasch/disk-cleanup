# Referência de UI/UX para o disk-cleanup

Documento de referência para orientar o design da interface do **disk-cleanup**, gerenciador de espaço em disco para desktop Linux distribuído como AppImage. A interface seguirá o Material Design 3; este documento **não** trata de Material e se concentra em princípios gerais de usabilidade, visualização de dados, ações destrutivas, alertas, acessibilidade e convenções de desktop Linux.

Cada princípio traz a fonte entre colchetes, por exemplo `[NNg-Heurísticas]`. As URLs completas estão na seção [Fontes](#fontes).

---

## 1. Contexto e premissas

Funções do app que guiam as recomendações:

| Área | Função |
| --- | --- |
| Visão geral | Resumo do espaço do disco, o que mais consome espaço |
| Monitoramento | Alertas de espaço baixo |
| Exploração | Diretórios mapeados escolhidos pelo usuário, lista de arquivos grandes |
| Limpeza de baixo risco | Lixeira, caches (npm, uv, pip, yarn, navegadores) |
| Limpeza de risco médio | Artefatos de build (`node_modules`, `target`, `.stack-work` etc.) |
| Limpeza de risco alto | Docker (build cache, containers parados, imagens) |

Premissa central: o app lida com **exclusão de dados**. Toda decisão de UI deve equilibrar rapidez (o usuário quer liberar espaço) com segurança (ninguém quer perder um projeto ou uma imagem Docker que demora horas para reconstruir).

---

## 2. As 10 heurísticas de Nielsen aplicadas ao disk-cleanup

Fonte de todas as heurísticas: `[NNg-Heurísticas]`.

| # | Heurística | Aplicação concreta no disk-cleanup |
| --- | --- | --- |
| 1 | **Visibilidade do status do sistema** | Mostrar sempre quando os dados foram coletados ("Atualizado há 3 min"), progresso da varredura com contagem de itens e bytes analisados, e o espaço liberado após cada limpeza. |
| 2 | **Correspondência entre o sistema e o mundo real** | Usar termos do usuário: "Cache do npm", "Dependências de projetos (node_modules)", "Imagens Docker sem uso". Evitar jargão interno como "dangling layers" sem explicação. Tamanhos sempre em unidade legível (GB, MB), nunca em bytes crus. |
| 3 | **Controle e liberdade do usuário** | Arquivos pessoais vão para a lixeira com botão "Desfazer" no toast. Permitir cancelar uma varredura ou uma limpeza em andamento. Desmarcar itens individualmente antes de confirmar. |
| 4 | **Consistência e padrões** | Mesma unidade de tamanho em todo o app (escolher GB decimal ou GiB binário e não misturar). Mesmo padrão de "selecionar, revisar, limpar" em todas as categorias. Seguir atalhos padrão do GNOME (seção 9). |
| 5 | **Prevenção de erros** | Nunca listar como "seguro para apagar" um `node_modules` de projeto com modificação recente sem destacar isso. Bloquear limpeza de diretórios de sistema. Pré-seleção apenas do que é regenerável. |
| 6 | **Reconhecer em vez de lembrar** | Na prévia de exclusão, mostrar caminho, tamanho e data do último acesso de cada item, para que o usuário reconheça o projeto sem precisar lembrar onde fica. |
| 7 | **Flexibilidade e eficiência de uso** | Ação "Limpar tudo que é seguro" para iniciantes; atalhos de teclado, filtros e seleção múltipla para usuários avançados. |
| 8 | **Estética e design minimalista** | Tela inicial com um número principal (espaço livre) e poucos cartões. Detalhes (lista completa de arquivos, caminhos) ficam um nível abaixo, por divulgação progressiva. |
| 9 | **Ajudar a reconhecer, diagnosticar e recuperar de erros** | "Não foi possível apagar 3 arquivos em /var/lib/docker: permissão negada. Rode a limpeza do Docker pelo comando `docker system prune` ou adicione seu usuário ao grupo docker." em vez de "Erro 13". |
| 10 | **Ajuda e documentação** | Tooltip ou texto curto explicando o que cada categoria é e se é seguro apagar ("O cache do pip é baixado de novo quando necessário"). |

---

## 3. Leis de UX relevantes

Fonte geral: `[LawsOfUX]` e páginas individuais citadas.

| Lei | Enunciado resumido | Aplicação no disk-cleanup |
| --- | --- | --- |
| **Hick** `[LawsOfUX-Hick]` | O tempo de decisão cresce com o número e a complexidade das opções. | Agrupar limpezas em poucas categorias (Lixeira, Caches, Builds, Docker). Não apresentar 15 botões de limpeza na tela inicial. |
| **Fitts** `[LawsOfUX-Fitts]` | O tempo para atingir um alvo depende da distância e do tamanho dele. | Botão de ação principal grande e próximo do resumo do que será liberado. Botões destrutivos não devem ficar colados a botões frequentes (distância reduz clique acidental). |
| **Jakob** `[LawsOfUX-Jakob]` | Usuários passam a maior parte do tempo em outros produtos e esperam que o seu funcione igual. | Seguir padrões de Baobab (Analisador de uso de disco do GNOME) e de gerenciadores de arquivos: lista com tamanho, ordenação por coluna, abrir pasta no gerenciador de arquivos. |
| **Miller** `[LawsOfUX-Miller]` | A memória de trabalho comporta poucos itens (em média 7 ± 2). | Top consumidores limitado a cerca de 5 a 7 itens na visão geral, com "Ver todos" para o resto. Agrupar números grandes em blocos legíveis. |
| **Tesler** `[LawsOfUX-Tesler]` | Todo sistema tem uma complexidade irredutível; alguém precisa lidar com ela. | O app absorve a complexidade: descobre sozinho onde ficam os caches de npm, uv, pip, yarn e navegadores, em vez de pedir que o usuário informe caminhos. |
| **Doherty** `[LawsOfUX-Doherty]` | Produtividade aumenta quando a resposta acontece em menos de 400 ms. | Exibir dados em cache imediatamente na abertura e atualizar em segundo plano. Feedback de clique instantâneo, mesmo que a operação demore. |
| **Von Restorff** `[LawsOfUX-VonRestorff]` | Entre itens semelhantes, o diferente é o mais lembrado. | Usar destaque visual apenas para o que exige atenção: alerta de disco crítico, item de risco alto. Se tudo for destacado, nada é. |
| **Pico-fim** `[LawsOfUX-PicoFim]` | A experiência é julgada pelo momento mais intenso e pelo final. | Terminar cada limpeza com um resumo positivo e concreto: "12,4 GB liberados. Espaço livre agora: 58 GB (23%)". |
| **Gradiente de objetivo** `[LawsOfUX-Gradiente]` | A motivação aumenta conforme a pessoa se aproxima da meta. | Na limpeza em lote, mostrar progresso acumulado ("7,1 de 12,4 GB liberados"). |

---

## 4. Hierarquia visual, tipografia, espaçamento e densidade

### 4.1 Hierarquia visual

- Hierarquia se constrói com **tamanho, peso, cor/contraste e espaçamento**; o elemento mais importante deve ser percebido primeiro `[NNg-Hierarquia]` `[IxDF-Hierarquia]`.
- Projetar primeiro em escala de cinza força a hierarquia a vir de tamanho, espaçamento e contraste, e não de cor `[RefactoringUI-Resumo]`.
- Para rebaixar algo, use cor mais clara ou tamanho menor; peso de fonte muito leve prejudica a leitura `[RefactoringUI-Resumo]`.
- "Teste do olhar semicerrado": itens relacionados se fundem, seções continuam distintas `[RefactoringUI-Resumo]`.

**Ordem de leitura sugerida para a tela inicial do disk-cleanup:**

1. Espaço livre do disco principal (número grande) e estado (normal, atenção, crítico).
2. Barra de uso do disco.
3. "Pode liberar X GB com segurança" e o botão principal.
4. Top consumidores.
5. Diretórios mapeados e detalhes.

### 4.2 Tipografia

- No máximo 3 a 4 tamanhos de texto por tela: número de destaque, título de seção, corpo, legenda.
- Números de tamanho em fonte com algarismos tabulares (largura fixa), para alinhar colunas de MB e GB em listas.
- Caminhos de arquivo em fonte monoespaçada ou com truncamento no meio (`~/projetos/…/node_modules`), preservando início e fim, que são as partes que identificam o item.
- Escrita: frases curtas e diretas, linguagem do usuário `[GNOME-Escrita]`. Em português, usar capitalização de frase em rótulos e mensagens ("Limpar cache do npm", e não "Limpar Cache Do Npm").

### 4.3 Espaçamento e grid

- Escala de espaçamento baseada em uma unidade (4 ou 8 px) e seus múltiplos; evitar valores arbitrários `[RefactoringUI-Resumo]`.
- Proximidade indica relação: o rótulo do tamanho fica colado ao nome do item; seções diferentes ficam mais afastadas `[RefactoringUI-Resumo]`.
- Começar com mais espaço em branco do que parece necessário e reduzir depois `[RefactoringUI-Resumo]`.
- Grid de colunas para os cartões do painel; a lista de arquivos grandes usa colunas alinhadas (nome, caminho, tamanho alinhado à direita, data).

### 4.4 Densidade de informação

- Dashboards servem para **consumo rápido**, com o mínimo de interação e de processamento cognitivo; exploração profunda fica em telas de detalhe `[NNg-Dashboards]`.
- Visão geral com baixa densidade (poucos números grandes). Telas de lista (arquivos grandes, artefatos de build) podem ser mais densas, com linhas compactas, porque o usuário está em modo de varredura e comparação.
- Divulgação progressiva para não sobrecarregar: "Não sobrecarregue as pessoas com muitos elementos de uma vez" `[GNOME-Princípios]`.

---

## 5. Dashboards e visualização de proporção e tamanho

### 5.1 Princípio perceptivo

- **Comprimento e posição 2D** são os atributos pré-atentivos que melhor representam quantidade; gráficos de barras ordenados permitem comparar valores rapidamente `[NNg-Dashboards]`.
- Pizza, donut, gauge e radar dependem de área e ângulo e comunicam mal relações quantitativas `[NNg-Dashboards]`.
- **Nunca usar 3D**: distorce área e alinhamento, principalmente em pizzas e treemaps `[NNg-Dashboards]`.

### 5.2 Quando usar cada visualização

| Visualização | Quando usar no disk-cleanup | Cuidados |
| --- | --- | --- |
| **Barra horizontal empilhada** | Uso total do disco (usado por categoria + livre). Uma barra só, ocupando a largura do cartão. | Poucas categorias (até 5 ou 6), "Outros" agrupado. Rótulo com valor ao lado de cada segmento ou em legenda. |
| **Barras horizontais ordenadas** | "O que mais consome espaço", tamanho por categoria de limpeza, top diretórios, arquivos grandes. É a visualização padrão. | Ordenar do maior para o menor; mostrar o número ao lado da barra; escala começando em zero. |
| **Treemap** | Visão exploratória de um diretório mapeado com muitos itens de tamanhos muito diferentes. | Bom para hierarquias grandes, ruim para comparação precisa `[Busca-Hierárquicos]`. Não anotar mais de 3 níveis, priorizar o nível mais alto, e torná-lo interativo (clicar para descer) `[DataToViz-Treemap]`. |
| **Sunburst / anéis** | Alternativa ao treemap para mostrar estrutura de pastas (o Baobab oferece anéis e treemap) `[Busca-Baobab]`. | Usa ângulo, que é menos preciso que comprimento `[NNg-Dashboards]`; manter poucos anéis `[Busca-Hierárquicos]`. Sunburst é "um conjunto de donuts aninhados" `[DataToViz-Sunburst]`. Tratar como opcional, nunca como única visão. |
| **Pizza / donut / gauge** | Evitar. Se usado para "% do disco usado", acompanhar sempre do valor numérico. | Comparação imprecisa `[NNg-Dashboards]`. |

**Recomendação para o disk-cleanup:** barras como padrão (visão geral e listas); treemap como modo opcional de exploração em diretórios mapeados; sunburst apenas se houver demanda, e sempre com lista lateral sincronizada como no Baobab `[Busca-Baobab]`.

### 5.3 Regras de rotulagem de dados

- Sempre exibir o valor numérico ao lado do elemento gráfico. Isso torna o gráfico legível sem depender de cor e dispensa contraste entre fatias para compreensão `[WCAG-NãoTexto]`.
- Mostrar tamanho absoluto e relativo: "18,2 GB (7% do disco)".
- Tooltip com nome completo e tamanho ao passar o mouse, como no Baobab `[Busca-Baobab]`, mas a informação essencial não pode existir **só** no tooltip.

---

## 6. Ações destrutivas

### 6.1 Princípios

- Ações destrutivas devem ter **confirmação ou desfazer**; desfazer costuma ser melhor, porque usuários clicam por hábito em diálogos de confirmação sem ler `[GNOME-Diálogos]`.
- "Permita que ações destrutivas sejam desfeitas em vez de pedir confirmação" `[GNOME-Princípios]`.
- Confirmação só para ações de **consequência séria**, especialmente as irreversíveis; nunca para ações rotineiras, senão o usuário passa a ignorá-las `[NNg-Confirmação]`.
- A confirmação deve ser **específica**: dizer exatamente o que será apagado, em termos do usuário; evitar "Tem certeza?" `[NNg-Confirmação]`.
- Botões que descrevem o resultado ("Apagar 12 imagens", "Manter imagens") em vez de "Sim/Não" `[NNg-Confirmação]`.
- Dizer apenas "estes 2 itens" não informa quais serão apagados; mostrar nomes e informação de apoio `[NNg-Confirmação]`.
- Botão de cancelar primeiro (à esquerda); **não** associar Enter à ação destrutiva; Esc cancela; foco inicial no controle que se espera que o usuário use `[GNOME-Diálogos]`.
- Diálogos só aparecem em resposta direta a uma ação do usuário, nunca de surpresa `[GNOME-Diálogos]`.
- Toast com botão "Desfazer" é o uso típico após uma ação destrutiva reversível `[GNOME-Toasts]`.

### 6.2 Matriz de risco proposta para o disk-cleanup

Classificação de autoria do projeto, derivada dos princípios acima.

| Categoria | Reversível? | Padrão de UI |
| --- | --- | --- |
| Arquivos grandes do usuário | Sim, via lixeira | Mover para a lixeira + toast "Movido para a lixeira. Desfazer". Sem diálogo. |
| Esvaziar lixeira | Não | Diálogo de confirmação com quantidade e tamanho: "Apagar permanentemente 214 itens (3,8 GB)?" Botões "Cancelar" e "Esvaziar lixeira". |
| Caches (npm, uv, pip, yarn, navegadores) | Não, mas regenerável | Prévia com tamanho por cache e aviso do custo ("serão baixados de novo quando necessário"). Confirmação leve inline (o próprio botão "Limpar 4,2 GB" após a revisão). Recomendar fechar o navegador antes de limpar o cache dele. |
| Artefatos de build (`node_modules`, `target`, `.stack-work`) | Não, mas regenerável com tempo | Lista com caminho do projeto, tamanho e última modificação. Pré-selecionar apenas projetos sem uso há muito tempo. Diálogo de confirmação listando projetos afetados. |
| Docker: build cache | Não, regenerável | Confirmação específica com tamanho recuperável. |
| Docker: containers parados e imagens | Não; podem conter estado ou levar muito tempo para reconstruir | Diálogo de confirmação com lista de nomes/tags, tamanho e data de criação. Nunca pré-selecionar imagens em uso. Botão "Remover 5 imagens (7,3 GB)". |

### 6.3 Fluxo padrão "Selecionar, revisar, limpar"

1. **Selecionar** a categoria ou itens.
2. **Revisar** a prévia: lista do que será apagado, com caminho, tamanho e data; total recuperável em destaque; itens podem ser desmarcados.
3. **Limpar**: botão com verbo e quantidade ("Liberar 12,4 GB").
4. **Progresso** por item com possibilidade de cancelar.
5. **Resultado**: espaço realmente liberado, itens que falharam e por quê, e "Desfazer" quando aplicável.

Regras complementares:

- Mostrar o **total recuperável estimado** antes e o **total efetivamente liberado** depois; se divergirem, explicar (por exemplo, arquivos em uso ou espaço compartilhado entre camadas Docker).
- Distinguir visualmente "mover para a lixeira" de "apagar permanentemente" no texto do botão e no ícone.
- Ação destrutiva com estilo visual de destrutivo, mas nunca como o único botão de destaque da tela inicial.

---

## 7. Alertas e notificações de espaço baixo

### 7.1 Escolha do canal

| Canal | Quando usar no disk-cleanup | Fonte |
| --- | --- | --- |
| **Notificação do sistema** | Disco crítico detectado com o app fechado ou em segundo plano; varredura longa concluída. | Notificações servem para eventos relevantes enquanto o usuário está em outros apps, como fim de operação longa `[GNOME-Notificações]`. |
| **Banner** | Estado persistente dentro do app: "Espaço livre abaixo de 10%" ou "Docker indisponível". | Banners comunicam estados persistentes `[GNOME-Banners]`. |
| **Toast** | Evento pontual com o app em uso: "Cache do pip limpo. 1,2 GB liberados." | Toasts são para eventos individuais, não estados contínuos `[GNOME-Toasts]`. |
| **Indicador inline** | Selo "Atenção" no cartão do disco ou ao lado de uma categoria grande. | Indicadores são contextuais e não interrompem `[NNg-Notificações]`. |

- Não usar toast para erro importante: mensagens que somem sozinhas passam despercebidas `[NNg-Notificações]`.
- Notificações do GNOME devem ser compreensíveis só pelo título e podem ter até três botões de ação; clicar no corpo leva à parte relevante do app `[GNOME-Notificações]`.
- Diferenciar notificações que **exigem ação** das **passivas** `[NNg-Notificações]`.
- Respeitar o tempo e a atenção das pessoas; não interromper sem necessidade `[GNOME-Princípios]`.

### 7.2 Severidade e limiares

- Usar **níveis de severidade visualmente distintos**, reconhecíveis antes da leitura do texto `[Busca-FadigaAlertas]`.
- Limiar baixo demais gera falso positivo; alto demais esconde problema real `[Busca-FadigaAlertas]`.
- Alertas específicos e acionáveis: nome do recurso, métrica e limiar `[Busca-FadigaAlertas]`.

**Proposta de limiares para o disk-cleanup** (decisão do projeto, configurável pelo usuário):

| Nível | Condição sugerida | Comportamento |
| --- | --- | --- |
| Normal | Livre ≥ 15% **e** ≥ 20 GB | Nenhum alerta. |
| Atenção | Livre < 15% **ou** < 20 GB | Indicador inline e banner dentro do app. Sem notificação do sistema. |
| Crítico | Livre < 5% **ou** < 5 GB | Notificação do sistema (uma vez por cruzamento de limiar) com ação "Abrir disk-cleanup". |

Regras anti-irritação:

- Usar **porcentagem e valor absoluto** juntos, porque 10% de um disco de 2 TB é muito diferente de 10% de 128 GB.
- **Histerese**: só notificar de novo depois que o disco voltar ao normal e cruzar o limiar outra vez.
- Opção "Lembrar mais tarde" (adiar por 24 h) e opção de desligar notificações por disco.
- Texto do alerta com ação: "Disco /home com 3,1 GB livres (2%). Você pode liberar cerca de 9 GB em caches e builds." Botões: "Revisar limpeza", "Adiar".

---

## 8. Estados: vazio, carregamento, progresso, erro e permissões

### 8.1 Tempos de resposta

- **0,1 s**: sensação de reação instantânea; **1 s**: limite para não interromper o fluxo de pensamento; **10 s**: limite para manter a atenção, acima disso é preciso indicar progresso e permitir interromper `[NNg-TemposResposta]`.
- Indicador em loop para esperas de 2 a 9 s; indicador de porcentagem para 10 s ou mais. Como a duração nem sempre é previsível, reduzir o corte para usar barra de porcentagem com mais frequência `[NNg-Progresso]`.
- Para cargas abaixo de 1 s, não exibir skeleton nem spinner, porque o "piscar" incomoda `[NNg-Skeleton]`.

### 8.2 Varredura longa

- Barra de progresso indicando o tempo restante; se a estimativa estourar, pausar em 100% com "Quase pronto"; modo de atividade (indeterminado) só quando for impossível estimar, e não por longos períodos `[GNOME-Progresso]`.
- Texto de progresso com unidades da tarefa: "18.430 de 52.000 arquivos analisados" ou "12,1 de 30 GB analisados"; estimativa com "cerca de": "Cerca de 2 minutos restantes" `[GNOME-Progresso]`.
- Percentual também é adequado para processar uma série de registros, mesmo que leve menos de 10 s `[NNg-Progresso]`.
- Recomendações do projeto:
  - Mostrar **resultados parciais** à medida que chegam (os maiores diretórios aparecem antes do fim).
  - Botão "Cancelar varredura" sempre visível.
  - Ao terminar com a janela fora de foco, enviar notificação "Varredura concluída" `[GNOME-Notificações]`.

### 8.3 Estados vazios

- Usar o estado vazio para **comunicar o status do sistema**, dar **dicas de aprendizado no contexto** e oferecer **caminho direto para a tarefa principal** `[NNg-EstadosVazios]`.
- Página de placeholder: imagem, título que comunica o estado e orienta, descrição opcional e controle para a ação relevante; placeholders simbólicos devem ser discretos `[GNOME-Placeholder]`.

Exemplos para o disk-cleanup:

| Situação | Título | Descrição | Ação |
| --- | --- | --- | --- |
| Nenhum diretório mapeado | "Nenhum diretório mapeado" | "Adicione pastas para acompanhar o tamanho delas ao longo do tempo." | "Adicionar diretório" |
| Lixeira vazia | "A lixeira está vazia" | "Não há nada para liberar aqui." | (nenhuma) |
| Nenhum artefato de build | "Nenhum artefato de build encontrado" | "Procuramos em ~/projetos. Mude as pastas de busca nas preferências." | "Escolher pastas" |
| Docker não instalado | "Docker não encontrado" | "Instale o Docker para ver imagens e containers." | (link de ajuda) |

### 8.4 Erros

- Mensagens visíveis, próximas da origem do erro, com destaque visual reconhecível `[NNg-Erros]` `[NNg-Heurísticas]`.
- Linguagem humana, descrição precisa do problema, conselho construtivo e sem culpar o usuário; códigos de erro só como detalhe técnico `[NNg-Erros]`.
- Em limpeza em lote, falha parcial não deve esconder o sucesso: "9,8 GB liberados. 3 itens não puderam ser apagados." com "Ver detalhes".

### 8.5 Permissões (sem sudo)

Recomendações do projeto, aplicando `[NNg-Erros]` e a heurística 9 `[NNg-Heurísticas]`:

- O app roda como usuário comum. Itens que exigem privilégio (por exemplo, `/var/lib/docker`, caches de sistema) aparecem marcados com ícone de cadeado **e texto** "Requer permissão de administrador".
- Explicar a alternativa: pedir elevação pontual pelo mecanismo do sistema (por exemplo, polkit) ou mostrar o comando equivalente para copiar.
- Tamanhos que não puderam ser lidos aparecem como "Tamanho desconhecido (sem permissão)", nunca como 0 B, para não induzir conclusão errada.
- Docker sem acesso ao socket: banner explicando "Seu usuário não tem acesso ao Docker" com o passo para resolver.

---

## 9. Acessibilidade

### 9.1 Contraste

- Texto: contraste mínimo **4,5:1**; texto grande (18 pt, ou 14 pt em negrito): **3:1** (WCAG 1.4.3, AA) `[WCAG22]` `[WCAG-Contraste]`.
- Componentes de interface e objetos gráficos necessários para entender o conteúdo (bordas de campos, segmentos de barra, fatias de gráfico, ícone de estado): **3:1** contra as cores adjacentes (WCAG 1.4.11, AA) `[WCAG-NãoTexto]`.
- Em gráficos, se os segmentos não tiverem 3:1 entre si, adicionar borda/separador ou exibir rótulos com valores que tragam a mesma informação `[WCAG-NãoTexto]`.
- Verificar contraste nos dois temas, claro e escuro.

### 9.2 Não depender só de cor

- Cor não pode ser o único meio de transmitir informação (WCAG 1.4.1, A); usar também forma ou texto `[WCAG-Cor]`.
- Instruções não podem depender apenas de características sensoriais como cor, forma ou posição (WCAG 1.3.3) `[WCAG22]`.
- Aplicação: severidade de alerta com **ícone + texto + cor** ("Crítico", "Atenção"); categorias no gráfico com rótulo; itens de risco alto com selo textual, não só vermelho.

### 9.3 Teclado e foco

- Toda função operável por teclado (WCAG 2.1.1) e foco sempre visível (WCAG 2.4.7) `[WCAG22]`.
- O elemento focado não pode ficar escondido por conteúdo do próprio app, como toasts ou barras fixas (WCAG 2.4.11 AA; 2.4.12 AAA exige que nenhuma parte fique oculta) `[WCAG22]`.
- Remover o contorno de foco por estilo é falha comum (F78) `[WCAG-NãoTexto]`.
- Alvos de clique com pelo menos **24 × 24 px**, ou espaçamento equivalente (WCAG 2.5.8, AA) `[WCAG22]`.
- Navegação padrão do GNOME: Tab/Shift+Tab, Enter ativa, Espaço alterna, F10 abre o menu principal, Shift+F10 abre o menu de contexto, Esc fecha elementos transitórios `[GNOME-Teclado]`.
- Ao abrir um diálogo, colocar o foco no controle esperado `[GNOME-Diálogos]`.
- Gráficos (treemap, barras) devem ter equivalente navegável por teclado, como a lista ordenada ao lado.
- Consultar as diretrizes de acessibilidade do GNOME ao validar a integração com leitores de tela `[GNOME-Acessibilidade]`.

---

## 10. Convenções de app desktop Linux (GNOME HIG)

### 10.1 Princípios gerais

- Fazer uma coisa e fazer bem; focar em uma situação de uso; ações frequentes ao alcance, as menos importantes mais distantes `[GNOME-Princípios]`.
- Antecipar e prevenir erros; preferir desfazer a confirmar; respeitar tempo e atenção `[GNOME-Princípios]`.

### 10.2 Janela e barra de título

- Barra de cabeçalho com poucos controles, organizados em três pontos de alinhamento (início, centro, fim); deixar espaço livre para arrastar a janela; todos os controles com tooltip `[GNOME-HeaderBar]`.
- Botões de ação principal no início, título ou alternador de visões no centro, menu principal no fim `[GNOME-HeaderBar]`.
- O conteúdo da barra muda conforme a visão ativa, mostrando só o que é relevante `[GNOME-HeaderBar]`.
- Sugestão de estrutura: alternador de visões com "Visão geral", "Limpeza", "Arquivos grandes", "Diretórios"; à direita, botão "Atualizar" e menu principal (Preferências, Atalhos de teclado, Sobre).
- Mesmo usando Material Design 3, manter o comportamento esperado pelo desktop: redimensionamento para larguras estreitas, botões de janela consistentes com o sistema, e tamanho/posição da janela lembrados.

### 10.3 Atalhos de teclado

- Usar os atalhos padrão do GNOME quando a função existir; atribuir atalhos às ações mais usadas, mas não a todas `[GNOME-Teclado]`.
- Atalhos novos: Ctrl + letra mnemônica; Shift+Ctrl para inverter ou estender; não usar Alt (conflita com teclas de acesso) nem Super (reservada ao sistema); preferir combinações fáceis com uma mão `[GNOME-Teclado]`.
- Proposta para o disk-cleanup (verificar conflitos com a lista padrão do GNOME):

| Atalho | Ação |
| --- | --- |
| Ctrl+R ou F5 | Atualizar varredura |
| Ctrl+F | Buscar/filtrar na lista |
| Ctrl+Z | Desfazer última movimentação para a lixeira |
| Ctrl+A | Selecionar todos na lista atual |
| Delete | Mover selecionados para a lixeira |
| Shift+Delete | Apagar permanentemente (sempre com confirmação) |
| Ctrl+, | Preferências |
| Ctrl+? | Janela de atalhos de teclado |
| Ctrl+Q | Sair |
| F10 | Menu principal |

### 10.4 Tema claro e escuro

- Apps devem seguir a preferência de estilo do sistema; quando houver preferência própria, oferecer três opções: claro, escuro e seguir o sistema `[GNOME-Estilo]`.
- O tema claro é o padrão recomendado para a maioria dos apps `[GNOME-Estilo]`.
- Validar cores de gráficos, severidades e contraste nos dois temas.

### 10.5 Escrita

- Textos curtos, diretos, na linguagem do usuário `[GNOME-Escrita]`.
- Capitalização de frase para rótulos e textos explicativos de diálogos e notificações `[GNOME-Escrita]`.

---

## 11. Checklist de revisão de UI do disk-cleanup

Usar antes de cada entrega de tela. Validação visual e de comportamento no app real é feita por pessoa, não só por teste automatizado.

### Visão geral e dados

- [ ] O espaço livre do disco é o primeiro elemento percebido (teste do olhar semicerrado).
- [ ] A tela indica quando os dados foram coletados.
- [ ] Quantidades usam barras ordenadas; nada de pizza 3D, gauge ou 3D em geral.
- [ ] Todo gráfico mostra valores numéricos, absolutos e percentuais.
- [ ] Treemap/sunburst, se existirem, são opcionais, interativos, com até 3 níveis anotados e lista equivalente.
- [ ] Mesma unidade de tamanho e mesmo formato numérico (vírgula decimal pt-BR) em todo o app.
- [ ] Top consumidores limitado a poucos itens, com "Ver todos".

### Ações destrutivas

- [ ] Cada categoria segue "Selecionar, revisar, limpar".
- [ ] A prévia mostra caminho, tamanho e data de cada item, e o total recuperável.
- [ ] Itens podem ser desmarcados antes de confirmar.
- [ ] Arquivos do usuário vão para a lixeira com "Desfazer" no toast.
- [ ] Ações irreversíveis têm confirmação específica (o quê, quantos, quanto), com botões que descrevem o resultado.
- [ ] Cancelar vem primeiro; Enter não dispara ação destrutiva; Esc cancela.
- [ ] Nenhum diálogo de confirmação em ação rotineira ou reversível.
- [ ] Resultado final mostra o espaço efetivamente liberado e as falhas.

### Alertas

- [ ] Níveis de severidade distintos por ícone, texto e cor.
- [ ] Limiares combinam porcentagem e valor absoluto e são configuráveis.
- [ ] Há histerese e opção de adiar; não há notificação repetida para o mesmo estado.
- [ ] Notificação do sistema só no nível crítico ou ao concluir operação longa.
- [ ] Erros importantes não aparecem apenas em toast.

### Estados

- [ ] Estado vazio de cada tela tem título, explicação e ação quando aplicável.
- [ ] Varredura longa tem barra com unidades ("X de Y arquivos"), estimativa com "cerca de" e botão cancelar.
- [ ] Resultados parciais aparecem durante a varredura.
- [ ] Nenhum spinner/skeleton em carga abaixo de 1 s.
- [ ] Mensagens de erro em linguagem humana, com causa e solução.
- [ ] Itens sem permissão aparecem como "sem permissão", nunca como 0 B, com caminho para resolver.
- [ ] Docker ausente ou inacessível tem estado próprio e explicativo.

### Acessibilidade

- [ ] Texto com contraste ≥ 4,5:1 (≥ 3:1 para texto grande), nos temas claro e escuro.
- [ ] Componentes e elementos de gráfico com contraste ≥ 3:1.
- [ ] Nenhuma informação transmitida só por cor.
- [ ] Todo fluxo funciona só com teclado; foco sempre visível e nunca coberto por toast.
- [ ] Alvos de clique com pelo menos 24 × 24 px.
- [ ] Foco inicial correto ao abrir diálogos.

### Convenções Linux/GNOME

- [ ] Barra de cabeçalho enxuta, com tooltips e espaço para arrastar.
- [ ] Atalhos padrão funcionam (Ctrl+Q, Ctrl+F, F10, Esc, Ctrl+?).
- [ ] Tema segue a preferência do sistema, com opção claro/escuro/sistema.
- [ ] Janela funciona em larguras estreitas e lembra tamanho e posição.
- [ ] Textos com capitalização de frase e linguagem do usuário.

---

## Fontes

Fontes abertas e consultadas diretamente:

| Rótulo | Fonte | URL |
| --- | --- | --- |
| NNg-Heurísticas | Nielsen Norman Group, *10 Usability Heuristics for User Interface Design* | https://www.nngroup.com/articles/ten-usability-heuristics/ |
| NNg-Confirmação | NN/g, *Confirmation Dialogs Can Prevent User Errors (If Not Overused)* | https://www.nngroup.com/articles/confirmation-dialog/ |
| NNg-Progresso | NN/g, *Progress Indicators Make a Slow System Less Insufferable* | https://www.nngroup.com/articles/progress-indicators/ |
| NNg-TemposResposta | NN/g, *Response Times: The 3 Important Limits* | https://www.nngroup.com/articles/response-times-3-important-limits/ |
| NNg-Skeleton | NN/g, *Skeleton Screens 101* | https://www.nngroup.com/articles/skeleton-screens/ |
| NNg-EstadosVazios | NN/g, *Designing Empty States in Complex Applications: 3 Guidelines* | https://www.nngroup.com/articles/empty-state-interface-design/ |
| NNg-Notificações | NN/g, *Indicators, Validations, and Notifications* | https://www.nngroup.com/articles/indicators-validations-notifications/ |
| NNg-Erros | NN/g, *Error-Message Guidelines* | https://www.nngroup.com/articles/error-message-guidelines/ |
| NNg-Dashboards | NN/g, *Dashboards: Making Charts and Graphs Easier to Understand* | https://www.nngroup.com/articles/dashboards-preattentive/ |
| NNg-Hierarquia | NN/g, *Visual Hierarchy in UX: Definition* | https://www.nngroup.com/articles/visual-hierarchy-ux-definition/ |
| IxDF-Hierarquia | Interaction Design Foundation, *Visual Hierarchy* | https://www.interaction-design.org/literature/topics/visual-hierarchy |
| LawsOfUX | Laws of UX (página inicial) | https://lawsofux.com/ |
| LawsOfUX-Hick | Laws of UX, *Hick's Law* | https://lawsofux.com/hicks-law/ |
| LawsOfUX-Fitts | Laws of UX, *Fitts's Law* | https://lawsofux.com/fittss-law/ |
| LawsOfUX-Jakob | Laws of UX, *Jakob's Law* | https://lawsofux.com/jakobs-law/ |
| LawsOfUX-Miller | Laws of UX, *Miller's Law* | https://lawsofux.com/millers-law/ |
| LawsOfUX-Tesler | Laws of UX, *Tesler's Law* | https://lawsofux.com/teslers-law/ |
| LawsOfUX-Doherty | Laws of UX, *Doherty Threshold* | https://lawsofux.com/doherty-threshold/ |
| LawsOfUX-VonRestorff | Laws of UX, *Von Restorff Effect* | https://lawsofux.com/von-restorff-effect/ |
| LawsOfUX-PicoFim | Laws of UX, *Peak-End Rule* | https://lawsofux.com/peak-end-rule/ |
| LawsOfUX-Gradiente | Laws of UX, *Goal-Gradient Effect* | https://lawsofux.com/goal-gradient-effect/ |
| DataToViz-Treemap | From Data to Viz, *Treemap* | https://www.data-to-viz.com/graph/treemap.html |
| DataToViz-Sunburst | From Data to Viz, *Sunburst* | https://www.data-to-viz.com/graph/sunburst.html |
| WCAG22 | W3C, *Web Content Accessibility Guidelines (WCAG) 2.2* | https://www.w3.org/TR/WCAG22/ |
| WCAG-Contraste | W3C, *Understanding SC 1.4.3 Contrast (Minimum)* | https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html |
| WCAG-NãoTexto | W3C, *Understanding SC 1.4.11 Non-text Contrast* | https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html |
| WCAG-Cor | W3C, *Understanding SC 1.4.1 Use of Color* | https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html |
| GNOME-HIG | GNOME Human Interface Guidelines (índice) | https://developer.gnome.org/hig/ |
| GNOME-Princípios | GNOME HIG, *Design Principles* | https://developer.gnome.org/hig/principles.html |
| GNOME-Teclado | GNOME HIG, *Keyboard* | https://developer.gnome.org/hig/guidelines/keyboard.html |
| GNOME-Diálogos | GNOME HIG, *Dialogs* | https://developer.gnome.org/hig/patterns/feedback/dialogs.html |
| GNOME-Toasts | GNOME HIG, *Toasts* | https://developer.gnome.org/hig/patterns/feedback/toasts.html |
| GNOME-Banners | GNOME HIG, *Banners* | https://developer.gnome.org/hig/patterns/feedback/banners.html |
| GNOME-Notificações | GNOME HIG, *Notifications* | https://developer.gnome.org/hig/patterns/feedback/notifications.html |
| GNOME-Placeholder | GNOME HIG, *Placeholder Pages* | https://developer.gnome.org/hig/patterns/feedback/placeholders.html |
| GNOME-Progresso | GNOME HIG, *Progress Bars* | https://developer.gnome.org/hig/patterns/feedback/progress-bars.html |
| GNOME-Estilo | GNOME HIG, *UI Styling* | https://developer.gnome.org/hig/guidelines/ui-styling.html |
| GNOME-HeaderBar | GNOME HIG, *Header Bars* | https://developer.gnome.org/hig/patterns/containers/header-bars.html |
| GNOME-Escrita | GNOME HIG, *Writing Style* | https://developer.gnome.org/hig/guidelines/writing-style.html |
| GNOME-Acessibilidade | GNOME HIG, *Accessibility* | https://developer.gnome.org/hig/guidelines/accessibility.html |

Fontes secundárias, vistas apenas como resumo em resultados de busca (não abertas integralmente; tratar como apoio, não como autoridade):

| Rótulo | Fonte | URL |
| --- | --- | --- |
| RefactoringUI-Resumo | Resenha do livro *Refactoring UI* (Wathan e Schoger) no DEV Community | https://dev.to/updivision/book-review-refactoring-ui-by-adam-wathan-steve-schoger-2f7m |
| Busca-Hierárquicos | Comparativos de treemap e sunburst | https://kindatechnical.com/data-visualization/treemaps-and-sunburst-charts-for-hierarchical-data.html |
| Busca-Hierárquicos | Domo, *Sunburst Chart: What It Is and When to Use It* | https://domo-webflow.domo.com/learn/charts/sunburst-chart |
| Busca-Baobab | Ubuntu Community Help Wiki, *Baobab* | https://help.ubuntu.com/community/Baobab |
| Busca-FadigaAlertas | DEV Community, *Alert fatigue and how to avoid it* | https://dev.to/godofgeeks/alert-fatigue-and-how-to-avoid-it-1g71 |
| Busca-FadigaAlertas | Canadian Web Hosting, *Fix alert fatigue* | https://blog.canadianwebhosting.com/fix-alert-fatigue-monitoring-tuning-small-teams/ |
| Busca-FadigaAlertas | Halo Lab, *Alert fatigue in healthcare software* | https://www.halo-lab.com/blog/alert-fatigue-in-healthcare |
| Busca-Desfazer | Andy Matuschak, *Prefer undo to confirmation steps* | https://notes.andymatuschak.org/zXH4ASvHNz488hCNgrBjQJK |
| Busca-CursoGoogle | Coursera, *Google UX Design Professional Certificate* (referência de formação; não usado como fonte de princípios) | https://www.coursera.org/professional-certificates/google-ux-design |
