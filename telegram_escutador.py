import asyncio
from datetime import datetime
import os
import re
from telethon import TelegramClient, events

# 1. Credenciais do Telegram
API_ID = 24172895  # Seu API ID
API_HASH = "3f91492d8a1cc8fea3a4eec5a24a6c66"  # Seu API Hash

# Nome de sessão atualizado para evitar AuthKeyDuplicatedError
SESSION_NAME = "sessao_telegram_vps_v2"

# Canal/Grupo autorizado para acionar ordens no MT5
# CANAL_PERMITIDO = "XAUUSD PROFIT TRADER"
CANAL_PERMITIDO = "Joas"

# Diretórios e Caminhos de Arquivo
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Pasta Comum do MetaTrader 5 (FILE_COMMON)
# Esta pasta é lida pelo EA com a flag FILE_COMMON (InpUsarCommon=true)
PASTA_COMUM_MT5 = os.path.expandvars(
    # r"%AppData%\MetaQuotes\Terminal\Common\Files"
    # r"C:\Users\Joas Souza\AppData\Roaming\MetaQuotes\Terminal\7BBBFA1A523B390AFF327BAAA5DD03D7\MQL5\Files"  # Fotmarkets (sem FILE_COMMON)
    # FTMO (sem FILE_COMMON)
    r"C:\Users\Joas Souza\AppData\Roaming\MetaQuotes\Terminal\81A933A9AFC5DE3C23B15CAB19C63850\MQL5\Files"
    # r"C:\Desenv\app_telegram_escutador"  # apenas para testes locais
)

os.makedirs(PASTA_COMUM_MT5, exist_ok=True)

timestamp_inicio = datetime.now().strftime("%Y%m%d_%H%M%S")
NOME_ARQUIVO_LOG = os.path.join(
    BASE_DIR, f"log_mensagens_{timestamp_inicio}.txt"
)
NOME_ARQUIVO_MT5 = os.path.join(PASTA_COMUM_MT5, "sinal_mt5.txt")

client = TelegramClient(SESSION_NAME, API_ID, API_HASH)


def formatar_numero(val: float) -> str:
    """Formata número removendo zeros decimais desnecessários."""
    if val.is_integer():
        return str(int(val))
    return f"{val:.5f}".rstrip("0").rstrip(".")


def extrair_e_formatar_sinal(texto: str) -> str:
    """Extrai os dados e formata em Chave=Valor para leitura direta no MQL5.
    Retorna None se PREÇO, SL ou TP1 forem vazios ou iguais a zero."""
    if not texto:
        return None

    texto_upper = texto.upper()

    # 1. Ação (BUY ou SELL)
    acao_match = re.search(r"\b(BUY|SELL)\b", texto_upper)
    acao = acao_match.group(1) if acao_match else None

    if not acao:
        return None

    # 2. Par de Moedas
    par_match = re.search(r"\b([A-Z]{6}|XAUUSD|BTCUSD)\b", texto_upper)
    par = par_match.group(1) if par_match else "XAUUSD"

    # 3. Preço de Entrada
    entrada_match = re.search(
        r"(?:BUY|SELL|ENTRADA|AT)[:\s]*([0-9]+\.?[0-9]*)", texto_upper
    )
    if not entrada_match:
        return None
    preco_str = entrada_match.group(1)

    # 4. Stop Loss (SL)
    sl_match = re.search(
        r"(?:SL|STOP LOSS)[:\s\.]*([0-9]+\.?[0-9]*)", texto_upper
    )
    if not sl_match:
        return None
    sl_str = sl_match.group(1)

    # 5. Validação numérica de PREÇO e SL
    try:
        preco_val = float(preco_str)
        sl_val = float(sl_str)
    except (ValueError, TypeError):
        return None

    # PREÇO e SL não podem ser zero ou negativos
    if preco_val <= 0 or sl_val <= 0:
        return None

    distancia_sl = abs(preco_val - sl_val)
    if distancia_sl <= 0:
        return None

    # 6. Cálculo do TP1 (mesmo tamanho do SL) e Trailing Stop (metade do SL)
    if acao == "BUY":
        tp1_val = preco_val + distancia_sl
    elif acao == "SELL":
        tp1_val = preco_val - distancia_sl
    else:
        return None

    # TP1 não pode ser zero ou negativo
    if tp1_val <= 0:
        return None

    trailing_val = distancia_sl / 2.0

    preco_formatado = formatar_numero(preco_val)
    sl_formatado = formatar_numero(sl_val)
    tp1_formatado = formatar_numero(tp1_val)
    trailing_formatado = formatar_numero(trailing_val)

    # Garantir que nenhum campo essencial seja vazio ou '0'
    if (
        not preco_formatado
        or preco_formatado == "0"
        or not sl_formatado
        or sl_formatado == "0"
        or not tp1_formatado
        or tp1_formatado == "0"
    ):
        return None

    # Montagem do bloco Chave=Valor para o MT5 (apenas TP1 e TRAILINGSTOP, descartando demais TPs)
    linhas = [
        f"PAR={par}",
        f"TIPO={acao}",
        f"PRECO={preco_formatado}",
        f"SL={sl_formatado}",
        f"TP1={tp1_formatado}",
        f"TRAILINGSTOP={trailing_formatado}",
    ]

    return "\n".join(linhas)


def salvar_em_log_historico(
    texto_bruto: str, sinal_formatado: str, origem: str, chat_id: int
):
    """Grava o registro completo e histórico no arquivo de log da execução."""
    hora = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    bloco_log = (
        f"{'='*60}\n"
        f"⏰ Data/Hora: {hora}\n"
        f"📌 Origem: {origem} (ID: {chat_id})\n"
        f"💬 Texto Bruto:\n{texto_bruto}\n\n"
    )
    if sinal_formatado:
        bloco_log += f"✅ Sinal Formatado Extraído:\n{sinal_formatado}\n"
    else:
        bloco_log += "ℹ️ NENHUM SINAL IDENTIFICADO NESTA MENSAGEM\n"

    bloco_log += f"{'='*60}\n"

    with open(NOME_ARQUIVO_LOG, "a", encoding="utf-8") as f:
        f.write(bloco_log)
        f.flush()


def salvar_para_mt5(sinal_formatado: str):
    """Grava o sinal na pasta comum para leitura pelo EA do MT5."""
    with open(NOME_ARQUIVO_MT5, "w", encoding="utf-8") as f:
        f.write(sinal_formatado)
        f.flush()


@client.on(events.NewMessage)
async def monitorar_todas_mensagens(event):
    texto_original = event.message.message

    if not texto_original:
        texto_original = "[Mensagem sem texto / Apenas mídia]"

    # Busca origem do chat
    try:
        chat = await event.get_chat()
        nome_chat = getattr(
            chat, "title", getattr(chat, "first_name", "Chat Desconhecido")
        )
    except Exception:
        nome_chat = "Chat Desconhecido"

    # Tenta extrair o sinal
    sinal_formatado = extrair_e_formatar_sinal(texto_original)

    # 1. Grava SEMPRE no log histórico de auditoria
    salvar_em_log_historico(
        texto_original, sinal_formatado, nome_chat, event.chat_id
    )

    # 2. FILTRO DE ORIGEM: Só grava para o MT5 se a mensagem vier de XAUUSD PROFIT TRADER
    if CANAL_PERMITIDO.upper() in nome_chat.upper():
        if sinal_formatado:
            salvar_para_mt5(sinal_formatado)
            print(f"\n🚀 SINAL PROCESSADO DA ORIGEM: {nome_chat}")
            print(sinal_formatado)
            print("-" * 50)
    else:
        if sinal_formatado:
            print(
                f"\n⚠️ Sinal ignorado para envio ao MT5. Origem '{nome_chat}' não autorizada."
            )


async def main():
    print("🚀 Monitor iniciado!")
    print(f"🎯 Canal Autorizado MT5: {CANAL_PERMITIDO}")
    print(f"📜 Log histórico: {NOME_ARQUIVO_LOG}")
    print(f"⚡ Arquivo do MT5: {NOME_ARQUIVO_MT5}\n")

    await client.start()
    print("✅ Conectado com sucesso! Aguardando novas mensagens...")
    await client.run_until_disconnected()


if __name__ == "__main__":
    asyncio.run(main())
