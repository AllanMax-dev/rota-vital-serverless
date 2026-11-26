# Rota Vital · Função serverless de guia de transporte

Atividade individual 1 (Serverless) · Infraestrutura de Software · ADS · CESAR School · 2026.2
Aluno: Allan Max de Jesus Rodrigues de Lima ([AllanMax-dev](https://github.com/AllanMax-dev))

Função HTTP que recebe uma requisição do Rota Vital (`POST /guias`) e devolve a guia de transporte das bolsas solicitadas pelo hospital.

## Caminho escolhido

**Caminho A: AWS SAM CLI local**, com Python 3.12 e Docker. Tudo roda no computador, sem conta na AWS.

## Estrutura

```
.
├── template.yaml          # Função, rota POST /guias e Timeout (Globals)
├── samconfig.toml         # Configuração do SAM CLI
├── hello_world/app.py     # Handler da função (código do Passo 2)
├── events/pedido.json     # Evento API Gateway (aws-proxy) usado no sam local invoke
├── tests/unit/            # Testes unitários do handler (pytest)
└── evidencias/            # Prints dos comandos e das saídas
```

## Contrato da função

**Entrada** (`POST /guias`, JSON):

| Campo          | Tipo            | Obrigatório | Descrição                                       |
|----------------|-----------------|-------------|-------------------------------------------------|
| `requisicaoId` | string          | sim         | Identificador da requisição                     |
| `hospital`     | string          | não         | Hospital solicitante                            |
| `bolsas`       | lista de string | não         | Bolsas a transportar                            |
| `demorar`      | boolean         | não         | Faz a função dormir 5 s (teste de tempo limite) |

**Saída**:

- `201`: `{"guia": "G-<requisicaoId>", "hospital": ..., "bolsas": [...], "invocacaoNesteAmbiente": N}`
- `400`: `{"erro": "requisicaoId obrigatório"}`

## Pré-requisitos

- Docker Desktop rodando
- AWS SAM CLI (`sam --version`)
- Python 3.12
- No Windows: Git Bash ou WSL

## Como rodar

### Modo rápido (tudo de uma vez)

No Git Bash, dentro da pasta do projeto, com o Docker Desktop aberto:

```bash
./executar-atividade.sh
```

O script roda os Passos 1 a 5 do enunciado na ordem, salva a saída de cada comando e um print da tela em `evidencias/`, e preenche a tabela de resultados abaixo. No fim, o `template.yaml` fica com `Timeout: 10` (o ajuste do Passo 5).

Os comandos manuais estão logo abaixo, passo a passo.

### 1. Build

```bash
sam build
```

### 2. Invocação com evento (Passo 3)

O arquivo `events/pedido.json` já está no repositório. Para gerar de novo:

```bash
sam local generate-event apigateway aws-proxy --method POST --path guias \
    --body '{"requisicaoId":"R-001","hospital":"H-Recife","bolsas":["O-NEG-0142"]}' \
    > events/pedido.json
```

> **Atenção:** nas versões recentes do SAM CLI (testado na 1.174.1), o `generate-event` grava o `body` em Base64 (`"isBase64Encoded": true`). Como o handler faz `json.loads(event["body"])` direto, a invocação falha com `JSONDecodeError`. O `events/pedido.json` deste repositório já está com o `body` em texto puro e `"isBase64Encoded": false`, então o handler fica igual ao do enunciado. Se você gerar o evento de novo, refaça essa troca.

Invocar duas vezes, medindo o tempo:

```bash
time sam local invoke -e events/pedido.json
time sam local invoke -e events/pedido.json
```

### 3. Gatilho HTTP (Passo 4)

Sem reaproveitamento de ambiente:

```bash
sam local start-api
```

Em outro terminal, três vezes:

```bash
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
    -d '{"requisicaoId":"R-002","hospital":"H-Recife"}'
```

Depois, parar o servidor (Ctrl+C) e repetir com reaproveitamento:

```bash
sam local start-api --warm-containers LAZY
```

> **Atenção:** o `samconfig.toml` gerado pelo `sam init` vinha com `warm_containers = "EAGER"` para `local_start_api` e `local_start_lambda`. Com isso, o `start-api` reaproveitaria o container mesmo sem a flag e o experimento "sem reaproveitamento" não funcionaria. Essas duas seções foram removidas.

### 4. Tempo limite (Passo 5)

Com `Timeout: 3` no `template.yaml`:

```bash
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
    -d '{"requisicaoId":"R-003","demorar":true}'
```

Depois, mudar `Timeout: 3` para `Timeout: 10` em `Globals`, rodar `sam build`, subir o `sam local start-api` de novo e repetir o curl.

### 5. Testes unitários

```bash
pip install pytest
python -m pytest tests/unit -v
```

## Resultados dos experimentos

| Experimento                                 | Resultado observado |
|---------------------------------------------|---------------------|
| `sam local invoke`, 1ª execução | 176.87 s |
| `sam local invoke`, 2ª execução | 10.81 s |
| `start-api` sem flag (3 curls) | invocacaoNesteAmbiente = 1, 1, 1 |
| `start-api --warm-containers LAZY` (3 curls) | invocacaoNesteAmbiente = 1, 2, 3 |
| `demorar: true` com `Timeout: 3` | HTTP 502, função interrompida por tempo limite (3 s) |
| `demorar: true` com `Timeout: 10` | HTTP 201 em 9.423597s, guia G-R-003 gerada |

## Respostas

### 1. Por que a primeira invocação demorou mais que a segunda? O que acontece na fase de Init?

Na primeira invocação não existe nenhum ambiente pronto, então é preciso criar um do zero: no SAM local, isso significa baixar ou preparar a imagem do runtime e subir o container; no Lambda real, provisionar o micro-VM. Essa é a fase de Init, em que o runtime do Python sobe, o pacote da função é carregado e o código fora do handler (imports e variáveis globais, como `contador = 0`) roda uma vez. Isso é o cold start. A partir daí o ambiente está pronto e a próxima chamada vai direto para o handler (fase Invoke). No meu teste, a 1ª execução do `sam local invoke` levou 176,9 s, porque o SAM teve que montar a imagem do runtime, e a 2ª levou 10,8 s. O `sam local invoke` cria um container novo a cada execução, mas a imagem já estava em cache no Docker.

### 2. O que o campo `invocacaoNesteAmbiente` mostrou com e sem `--warm-containers`? O que isso diz sobre guardar estado numa variável global?

Sem a flag, o `sam local start-api` cria um container novo para cada requisição, então o contador sempre volta `1`. Com `--warm-containers LAZY`, o container é criado na primeira chamada e reaproveitado nas seguintes, e o contador sobe (`1`, `2`, `3`). Isso mostra que a variável global só sobrevive enquanto o mesmo ambiente estiver sendo reaproveitado. A plataforma decide quando criar, reaproveitar ou destruir ambientes, e várias instâncias podem rodar em paralelo, cada uma com o próprio contador. Por isso, variável global não serve para guardar estado de negócio: no máximo para cache (como uma conexão com o banco). Estado que precisa persistir vai para fora da função (banco de dados, DynamoDB, S3, Redis).

### 3. O que aconteceu com `demorar = true`? Qual é o tempo máximo de uma execução no Lambda, e o que fazer com um trabalho mais longo?

Com `Timeout: 3`, a função foi interrompida depois de 3 segundos, antes de terminar o `sleep(5)`. O SAM registrou o estouro de tempo e a chamada HTTP não recebeu a guia. Com `Timeout: 3`, a chamada voltou `HTTP 502` com a mensagem `Function 'HelloWorldFunction' timed out after 3 seconds`. Com `Timeout: 10`, a função terminou o `sleep(5)` e devolveu `201` com a guia `G-R-003`, em 9,4 s no total, contando a subida do container. No Lambda, o tempo máximo de uma execução é de 900 segundos (15 minutos). Para um trabalho mais longo, a saída é quebrar em etapas menores orquestradas pelo Step Functions, processar de forma assíncrona com uma fila (SQS) e devolver só um "recebido" ao cliente, ou levar o trabalho para um serviço sem esse limite, como ECS/Fargate ou AWS Batch.

### 4. Quanto custam 1 milhão de execuções com 128 MB e 100 ms (preços de us-east-1)?

- Requisições: 1.000.000 × US$ 0,20 / 1.000.000 = **US$ 0,20**
- Memória em GB: 128 MB / 1024 = 0,125 GB
- GB-s por execução: 0,125 GB × 0,1 s = 0,0125 GB-s
- GB-s totais: 0,0125 × 1.000.000 = 12.500 GB-s
- Computação: 12.500 × US$ 0,0000166667 = **US$ 0,2083**
- **Total: US$ 0,20 + US$ 0,2083 ≈ US$ 0,41**

Esse valor não conta a faixa sempre gratuita (1 milhão de requisições e 400 mil GB-s por mês). Com ela, esse volume sairia de graça.

### 5. Em que parte do Rota Vital uma função assim faria sentido, e em qual não faria?

Faz sentido em tarefas curtas, sem estado e disparadas por evento: gerar a guia de transporte quando uma requisição é aprovada, enviar notificações ao hospital e ao motorista, validar uma requisição recebida ou gerar um relatório periódico. São chamadas rápidas, com demanda irregular, em que pagar por execução sai mais barato que manter um servidor ligado.

Não faz sentido em partes que precisam de conexão contínua ou de baixa latência garantida: o rastreamento em tempo real da rota do transporte (WebSocket ou fluxo contínuo de localização), processos longos que passam de 15 minutos e fluxos críticos em que o cold start atrapalharia o atendimento. Também não serve para guardar o estado da requisição, que precisa ficar num banco de dados.

## Evidências

Pasta [`evidencias/`](evidencias/):

Cada passo tem a saída completa do terminal (`.txt`) e uma imagem (`.png`). Os passos com `start-api` também guardam o log do servidor (`.log`). As imagens 01 e 02 são capturas da janela do terminal. As imagens 03 a 08 foram geradas a partir dos arquivos `.txt` da mesma execução (25/11/2026), porque a captura automática registrou outra janela que estava em primeiro plano; o conteúdo é a saída real do terminal, sem alteração.

| Arquivo                     | Conteúdo                                                |
|-----------------------------|---------------------------------------------------------|
| `01-versoes`                | `sam --version`, `docker --version`, `python --version` |
| `02-build`                  | `sam build`                                             |
| `03-invoke-1`               | 1ª `sam local invoke` com o tempo                       |
| `04-invoke-2`               | 2ª `sam local invoke` com o tempo                       |
| `05-start-api-sem-warm`     | 3 curls sem `--warm-containers`                         |
| `06-start-api-lazy`         | 3 curls com `--warm-containers LAZY`                    |
| `07-timeout-3s`             | Erro de tempo limite com `Timeout: 3`                   |
| `08-timeout-10s`            | Resposta com `Timeout: 10`                              |

Vídeo (até 3 min): https://youtu.be/jtGAkMTiwpc

## Uso de IA

Declaração conforme a PO-CESAR-021.

- **Ferramenta:** Claude (Anthropic).
- **Finalidade:** apoio para montar a estrutura do projeto com `sam init`, adaptar o `template.yaml` (rota `POST /guias`), identificar dois problemas do ambiente (o `body` em Base64 no evento gerado e o `warm_containers = "EAGER"` no `samconfig.toml`), escrever os testes unitários e o script `executar-atividade.sh`, e revisar a redação do README e a conta de custo.
- **Como validei:** rodei todos os passos no meu computador com SAM CLI e Docker e conferi cada saída com o que o enunciado pede: o tempo das duas invocações, o contador com e sem `--warm-containers` e o erro de tempo limite antes e depois do ajuste. Refiz a conta de custo à mão e conferi o tempo máximo de 15 minutos na documentação de cotas do Lambda. As evidências estão em `evidencias/`.
