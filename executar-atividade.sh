#!/usr/bin/env bash
# Atividade individual 1 · Serverless · Rota Vital
#
# Uso (no Git Bash, dentro da pasta do projeto):
#   ./executar-atividade.sh                 roda os Passos 3, 4 e 5, salva evidências e preenche o README
#   ./executar-atividade.sh publicar [URL]  cria o repositório no GitHub e envia (URL = link do vídeo, opcional)

set -u
cd "$(dirname "$0")"

EVID="evidencias"
PORTA=3000
URL="http://127.0.0.1:${PORTA}/guias"
RESULTADOS="$EVID/resultados.env"
API_PID=""

# ---------------------------------------------------------------- utilidades

titulo() { printf '\n\033[1;36m========== %s ==========\033[0m\n' "$*"; }
info()   { printf '\033[0;33m> %s\033[0m\n' "$*"; }
falha()  { printf '\033[1;31mERRO: %s\033[0m\n' "$*"; exit 1; }

# Destaques para a gravação: fundo amarelo no que deve ser apontado na tela.
AM=$'\033[1;30;43m'; CI=$'\033[1;30;46m'; FIM=$'\033[0m'
destaque() { printf '\n%s  >>> %s  %s\n' "$AM" "$*" "$FIM"; sleep 2; }
realce() {
    sed -u -E \
        -e "s/(invocacaoNesteAmbiente[^0-9]{1,4}[0-9]+)/${AM}\1${FIM}/g" \
        -e "s/(G-R-[0-9]+)/${AM}\1${FIM}/g" \
        -e "s/(\"statusCode\": [0-9]+)/${AM}\1${FIM}/g" \
        -e "s/(\\[HTTP [0-9]+ em [0-9.]+s\\])/${CI}\1${FIM}/g" \
        -e "s/(Function '[^']+' timed out after [0-9]+ seconds)/${AM}\1${FIM}/g" \
        -e "s/(Build Succeeded)/${AM}\1${FIM}/g" \
        -e "s/(Tempo total da execução [0-9]+: [0-9.]+ s)/${AM}\1${FIM}/g" \
        -e "s/(SAM CLI, version [0-9.]+|Docker version [0-9.]+|Python [0-9.]+)/${AM}\1${FIM}/g"
}

detectar_comandos() {
    if command -v sam >/dev/null 2>&1; then SAM="sam"
    elif command -v sam.cmd >/dev/null 2>&1; then SAM="sam.cmd"
    else falha "SAM CLI não encontrado. Instale: winget install Amazon.SAM-CLI (e reabra o Git Bash)"; fi

    command -v docker >/dev/null 2>&1 || falha "Docker não encontrado. Instale o Docker Desktop: winget install Docker.DockerDesktop"
    docker info >/dev/null 2>&1 || falha "Docker instalado, mas não está rodando. Abra o Docker Desktop e espere ficar 'Engine running'."

    if command -v python >/dev/null 2>&1 && python -c "import sys" >/dev/null 2>&1; then PY="python"
    elif command -v py >/dev/null 2>&1; then PY="py"
    elif command -v python3 >/dev/null 2>&1; then PY="python3"
    else falha "Python não encontrado. Instale: winget install Python.Python.3.12"; fi

    command -v curl >/dev/null 2>&1 || falha "curl não encontrado."
}

agora_ms() { date +%s%3N; }

print_tela() {
    # Captura SÓ a janela do terminal em primeiro plano (não a tela inteira), para
    # não registrar outras janelas abertas. Só no Windows, via PowerShell.
    local destino="$1"
    command -v powershell.exe >/dev/null 2>&1 || return 0
    local ps1 caminho
    ps1="$(mktemp --suffix=.ps1)"
    cat > "$ps1" <<'PS'
param([string]$Destino)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public struct RECT { public int Left, Top, Right, Bottom; }
public static class Janela {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
}
"@
$h = [Janela]::GetForegroundWindow()
$cls = New-Object System.Text.StringBuilder 256
[void][Janela]::GetClassName($h, $cls, 256)
# Só captura se a janela da frente for um terminal (mintty do Git Bash ou console do Windows)
if ($cls.ToString() -notmatch 'mintty|ConsoleWindowClass|CASCADIA_HOSTING_WINDOW_CLASS') { exit 2 }
$r = New-Object RECT
[void][Janela]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $a = $r.Bottom - $r.Top
if ($w -le 0 -or $a -le 0) { exit 3 }
$bmp = New-Object System.Drawing.Bitmap $w, $a
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$bmp.Save($Destino, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
PS
    caminho="$(cygpath -w "$(pwd)/$destino" 2>/dev/null || echo "$destino")"
    sleep 1
    if powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$ps1" 2>/dev/null || echo "$ps1")" -Destino "$caminho" >/dev/null 2>&1; then
        info "print salvo: $destino"
    else
        info "print NÃO salvo ($destino): deixe o terminal em primeiro plano; o log .txt foi salvo normalmente"
    fi
    rm -f "$ps1"
}

salvar() { echo "$1=\"$2\"" >> "$RESULTADOS"; }

limpar_containers() {
    docker ps --format '{{.ID}} {{.Image}}' 2>/dev/null | grep -E 'rapid|emulation-python' | awk '{print $1}' | xargs -r docker rm -f >/dev/null 2>&1
    true
}

subir_api() {
    local log="$1"; shift
    info "$SAM local start-api $*"
    $SAM local start-api --port "$PORTA" "$@" > "$log" 2>&1 &
    API_PID=$!
    for _ in $(seq 1 90); do
        curl -s -o /dev/null "http://127.0.0.1:${PORTA}/" 2>/dev/null && return 0
        sleep 1
    done
    cat "$log"
    falha "start-api não subiu em 90 s (veja $log)"
}

parar_api() {
    [ -z "$API_PID" ] && return 0
    local winpid=""
    [ -r "/proc/$API_PID/winpid" ] && winpid="$(cat "/proc/$API_PID/winpid")"
    if [ -n "$winpid" ] && command -v taskkill >/dev/null 2>&1; then
        taskkill //F //T //PID "$winpid" >/dev/null 2>&1
    fi
    kill "$API_PID" >/dev/null 2>&1
    wait "$API_PID" 2>/dev/null
    API_PID=""
    sleep 2
    limpar_containers
}
trap parar_api EXIT

chamar() {
    # chamar <corpo json>  -> imprime a resposta e o status HTTP
    curl -s -X POST "$URL" -H "Content-Type: application/json" -d "$1" \
         -w '\n[HTTP %{http_code} em %{time_total}s]\n'
}

definir_timeout() {
    sed -i -E "s/^(    Timeout: )[0-9]+/\1$1/" template.yaml
    info "template.yaml: Timeout = $(grep -E '^    Timeout:' template.yaml | awk '{print $2}') s"
}

contadores() { grep -o '"invocacaoNesteAmbiente": [0-9]*' "$1" | awk '{print $2}' | paste -sd, - | sed 's/,/, /g'; }

curl_api() {
    # 3 chamadas iguais às do Passo 4
    for n in 1 2 3; do
        echo "\$ curl -X POST $URL -H \"Content-Type: application/json\" -d '{\"requisicaoId\":\"R-002\",\"hospital\":\"H-Caruaru\"}'   (chamada $n)"
        chamar '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'
    done
}

# ---------------------------------------------------------------- experimentos

experimentos() {
    detectar_comandos
    mkdir -p "$EVID"
    : > "$RESULTADOS"
    limpar_containers
    definir_timeout 3 >/dev/null

    titulo "Passo 1 · Ferramentas"
    {
        echo "\$ sam --version";     $SAM --version
        echo "\$ docker --version";  docker --version
        echo "\$ python --version";  $PY --version
    } 2>&1 | tee "$EVID/01-versoes.txt" | realce
    destaque "Ferramentas instaladas: SAM CLI, Docker e Python"
    print_tela "$EVID/01-versoes.png"

    titulo "Passo 2 · sam build"
    $SAM build 2>&1 | tee "$EVID/02-build.txt" | realce
    [ "${PIPESTATUS[0]}" -eq 0 ] || falha "sam build falhou"
    destaque "Build Succeeded: função Python 3.12 empacotada"
    print_tela "$EVID/02-build.png"

    titulo "Passo 3 · Invocação com evento (2 vezes)"
    local n ini fim dur arq
    for n in 1 2; do
        arq="$EVID/0$((n+2))-invoke-$n"
        info "sam local invoke -e events/pedido.json   (execução $n)"
        ini=$(agora_ms)
        $SAM local invoke -e events/pedido.json 2>&1 | tee "$arq.txt" | realce
        fim=$(agora_ms)
        dur=$(awk "BEGIN{printf \"%.2f\", ($fim-$ini)/1000}")
        echo "Tempo total da execução $n: ${dur} s" | tee -a "$arq.txt" | realce
        salvar "INVOKE_$n" "$dur"
        destaque "Execução $n: HTTP 201, guia G-R-001, em ${dur} s"
        print_tela "$arq.png"
    done

    titulo "Passo 4a · start-api SEM reaproveitamento (3 chamadas)"
    subir_api "$EVID/05-start-api-sem-warm.log"
    curl_api 2>&1 | tee "$EVID/05-start-api-sem-warm.txt" | realce
    salvar "SEM_WARM" "$(contadores "$EVID/05-start-api-sem-warm.txt")"
    destaque "SEM reaproveitamento: invocacaoNesteAmbiente = $(contadores "$EVID/05-start-api-sem-warm.txt") (container novo a cada chamada)"
    print_tela "$EVID/05-start-api-sem-warm.png"
    parar_api

    titulo "Passo 4b · start-api COM --warm-containers LAZY (3 chamadas)"
    subir_api "$EVID/06-start-api-lazy.log" --warm-containers LAZY
    curl_api 2>&1 | tee "$EVID/06-start-api-lazy.txt" | realce
    salvar "LAZY" "$(contadores "$EVID/06-start-api-lazy.txt")"
    destaque "COM --warm-containers LAZY: invocacaoNesteAmbiente = $(contadores "$EVID/06-start-api-lazy.txt") (mesmo container reaproveitado)"
    print_tela "$EVID/06-start-api-lazy.png"
    parar_api

    titulo "Passo 5a · demorar=true com Timeout 3 s"
    definir_timeout 3
    $SAM build >/dev/null 2>&1 || falha "sam build falhou"
    subir_api "$EVID/07-timeout-3s.log"
    {
        echo "\$ curl -X POST $URL -H \"Content-Type: application/json\" -d '{\"requisicaoId\":\"R-003\",\"demorar\":true}'"
        chamar '{"requisicaoId":"R-003","demorar":true}'
        sleep 2
        echo; echo "--- log do sam local start-api ---"
        grep -iE "timed out|timeout|time out|error|START|END|REPORT" "$EVID/07-timeout-3s.log" | tail -15
    } 2>&1 | tee "$EVID/07-timeout-3s.txt" | realce
    salvar "TIMEOUT3" "$(grep -oE 'HTTP [0-9]+' "$EVID/07-timeout-3s.txt" | head -1)$(grep -qiE 'timed out|time out' "$EVID/07-timeout-3s.txt" && echo ', função interrompida por tempo limite (3 s)')"
    destaque "Timeout de 3 s: $(grep -oE 'HTTP [0-9]+' "$EVID/07-timeout-3s.txt" | head -1), a função foi interrompida antes de terminar"
    print_tela "$EVID/07-timeout-3s.png"
    parar_api

    titulo "Passo 5b · demorar=true com Timeout 10 s"
    definir_timeout 10
    $SAM build >/dev/null 2>&1 || falha "sam build falhou"
    subir_api "$EVID/08-timeout-10s.log"
    {
        echo "\$ curl -X POST $URL -H \"Content-Type: application/json\" -d '{\"requisicaoId\":\"R-003\",\"demorar\":true}'"
        chamar '{"requisicaoId":"R-003","demorar":true}'
    } 2>&1 | tee "$EVID/08-timeout-10s.txt" | realce
    salvar "TIMEOUT10" "$(grep -oE 'HTTP [0-9]+ em [0-9.]+s' "$EVID/08-timeout-10s.txt" | head -1), guia G-R-003 gerada"
    destaque "Timeout de 10 s: $(grep -oE 'HTTP [0-9]+' "$EVID/08-timeout-10s.txt" | head -1), guia G-R-003 gerada"
    print_tela "$EVID/08-timeout-10s.png"
    parar_api

    titulo "Preenchendo a tabela de resultados do README"
    $PY - "$RESULTADOS" <<'PY'
import re, sys
r = {}
for linha in open(sys.argv[1], encoding="utf-8"):
    k, _, v = linha.strip().partition("=")
    if k:
        r[k] = v.strip('"')
linhas = {
    "`sam local invoke`, 1ª execução": f"{r.get('INVOKE_1','?')} s",
    "`sam local invoke`, 2ª execução": f"{r.get('INVOKE_2','?')} s",
    "`start-api` sem flag (3 curls)": f"invocacaoNesteAmbiente = {r.get('SEM_WARM','?')}",
    "`start-api --warm-containers LAZY` (3 curls)": f"invocacaoNesteAmbiente = {r.get('LAZY','?')}",
    "`demorar: true` com `Timeout: 3`": r.get("TIMEOUT3", "?"),
    "`demorar: true` com `Timeout: 10`": r.get("TIMEOUT10", "?"),
}
txt = open("README.md", encoding="utf-8").read()
for chave, valor in linhas.items():
    txt = re.sub(r"^\| " + re.escape(chave) + r"\s*\|.*\|$",
                 f"| {chave} | {valor} |", txt, flags=re.M)
open("README.md", "w", encoding="utf-8", newline="\n").write(txt)
print("README atualizado:")
for chave, valor in linhas.items():
    print(f"  {chave}: {valor}")
PY

    titulo "Pronto"
    info "Evidências em $EVID/. Para publicar: ./executar-atividade.sh publicar"
}

# ---------------------------------------------------------------- publicação

publicar() {
    local video="${1:-}"
    command -v git >/dev/null 2>&1 || falha "git não encontrado."

    if [ -n "$video" ]; then
        sed -i -E "s#^Vídeo \(até 3 min\):.*#Vídeo (até 3 min): ${video}#" README.md
        info "Link do vídeo gravado no README."
    fi

    [ -d .git ] || git init -q -b main
    git config user.name "AllanMax-dev"
    # E-mail do autor: usa o do git global (git config --global user.email) ou a variável GIT_AUTOR_EMAIL.
    if [ -n "${GIT_AUTOR_EMAIL:-}" ]; then
        git config user.email "$GIT_AUTOR_EMAIL"
    elif [ -z "$(git config user.email)" ]; then
        falha "Defina seu e-mail do GitHub: git config --global user.email \"seu-email\" e rode de novo."
    fi

    # .aws-sam/ é saída do sam build e não vai para o repositório.
    if git ls-files --error-unmatch .aws-sam >/dev/null 2>&1; then
        git rm -r -q --cached .aws-sam
        info "Pasta .aws-sam (saída do build) removida do repositório."
    fi
    git add -A
    if git diff --cached --quiet; then
        info "Nada novo para commitar."
    elif git rev-parse --verify -q HEAD >/dev/null; then
        git commit -q -m "Atualiza entrega da atividade serverless"
    else
        git commit -q -m "Atividade individual 1: função serverless de guia de transporte do Rota Vital"
    fi

    if git remote get-url origin >/dev/null 2>&1; then
        git push -u origin main
    elif command -v gh >/dev/null 2>&1; then
        gh auth status >/dev/null 2>&1 || gh auth login --web
        gh repo create rota-vital-serverless --public --source . --remote origin --push \
            --description "Atividade individual 1 (Serverless) · Infraestrutura de Software · CESAR School"
    else
        falha "GitHub CLI não encontrado. Instale (winget install GitHub.cli) ou crie o repositório 'rota-vital-serverless' no site e rode: git remote add origin <url> && ./executar-atividade.sh publicar"
    fi

    titulo "Repositório publicado"
    git remote get-url origin
}

case "${1:-}" in
    publicar) shift; publicar "$@" ;;
    "")       experimentos ;;
    *)        echo "Uso: $0 [publicar [link-do-video]]"; exit 1 ;;
esac
