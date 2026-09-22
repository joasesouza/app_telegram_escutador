import asyncio
from datetime import datetime
import os
import re
from telethon import TelegramClient, events

# 1. Suas credenciais do Telegram (obtenha em https://my.telegram.org)
API_ID = 24172895  # Substitua pelo seu API ID (número inteiro)
# Substitua pelo seu API Hash (string)
API_HASH = "3f91492d8a1cc8fea3a4eec5a24a6c66"

SESSION_NAME = "sessao_telegram_vps"

# 2. Arquivos de Saída
# Log Histórico (Cria um novo por execução do script)
timestamp_inicio = datetime.now().strftime("%Y%m%d_%H%M%S")
NOME_ARQUIVO_LOG = f"log_mensagens_{timestamp_inicio}.txt"

# Arquivo Fixo para o EA do MT5 ler (Sobrescreve/Atualiza a cada novo sinal)
# DICA: Para o MT5 ler diretamente, você pode colocar o caminho da pasta MQL5/Files do seu terminal
NOME_ARQUIVO_MT5 = "sinal_mt5.txt"

client = TelegramClient(SESSION_NAME, API_ID, API_HASH)


def extrair_e_formatar_sinal(texto: str) -> str:
    """Extrai par, ordem, preço de entrada, TPs e SL e padroniza para o formato do EA MT5:

    PAR ORDEM PRECO
    TP. XXX
    ...
    SL. XXX
    """
    texto_upper = texto.upper()

    # 1. Identifica Ação (BUY ou SELL)
    acao_match = re.search(r"\b(BUY|SELL)\b", texto_upper)
    acao = acao_match.group(1) if acao_match else None

    # Se a mensagem não contiver ação, ignora
    if not acao:
        return None

    # 2. Identifica Par de Moedas (ex: XAUUSD, EURUSD, GBPJPY)
    par_match = re.search(r"\b([A-Z]{6}|XAUUSD|BTCUSD)\b", texto_upper)
    par = par_match.group(1) if par_match else "XAUUSD"

    # 3. Identifica Preço de Entrada
    entrada_match = re.search(
        r"(?:BUY|SELL|ENTRADA|AT)[:\s]*([0-9]+\.?[0-9]*)", texto_upper
    )
    preco_entrada = entrada_match.group(1) if entrada_match else ""

    # 4. Captura todos os Take Profits (TPs)
    tps = re.findall(
        r"(?:TP|TP\d+|TAKE PROFIT)[:\s\.]*([0-9]+\.?[0-9]*)", texto_upper
    )

    # 5. Captura o Stop Loss (SL)
    sl_match = re.search(
        r"(?:SL|STOP LOSS)[:\s\.]*([0-9]+\.?[0-9]*)", texto_upper
    )
    sl = sl_match.group(1) if sl_match else ""

    # --- MONTAGEM DO TEXTO FORMATADO ---
    linhas = []

    # Cabeçalho: XAUUSD SELL 4374
    linha_cabecalho = f"{par} {acao}"
    if preco_entrada:
        linha_cabecalho += f" {preco_entrada}"
    linhas.append(linha_cabecalho)
    linhas.append("")  # Linha em branco

    # Bloco de TPs: TP. XXX
    if tps:
        for tp in tps:
            linhas.append(f"TP. {tp}")
        linhas.append("")  # Linha em branco

    # Bloco de SL: SL. XXX
    if sl:
        linhas.append(f"SL. {sl}")

    return "\n".join(linhas)


def salvar_em_log_historico(texto_bruto: str, sinal_formatado: str, origem: str, chat_id: int):
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
    """Grava o sinal no arquivo exclusivo que o EA do MT5 vai ler.
    
    Usamos o modo 'w' para que apenas o SINAL ATUAL fique no arquivo.
    """
    with open(NOME_ARQUIVO_MT5, "w", encoding="utf-8") as f:
        f.write(sinal_formatado)
        f.flush()


@client.on(events.NewMessage)
async def monitorar_todas_mensagens(event):
    texto_original = event.message.message

    if not texto_original:
        texto_original = "[Mensagem sem texto / Apenas mídia]"

    # Busca origem
    try:
        chat = await event.get_chat()
        nome_chat = getattr(chat, "title", getattr(chat, "first_name", "Chat Desconhecido"))
    except Exception:
        nome_chat = "Chat Desconhecido"

    # Tenta extrair e formatar o sinal
    sinal_formatado = extrair_e_formatar_sinal(texto_original)

    # 1. Salva SEMPRE no Log Histórico
    salvar_em_log_historico(texto_original, sinal_formatado, nome_chat, event.chat_id)

    # 2. Se for um sinal válido, grava no arquivo do MT5
    if sinal_formatado:
        salvar_para_mt5(sinal_formatado)
        print("\n🚀 NOVO SINAL PROCESSADO E ENVIADO PARA O MT5:")
        print(sinal_formatado)
        print("-" * 50)


async def main():
    print(f"🚀 Monitor iniciado!")
    print(f"📜 Log histórico: {NOME_ARQUIVO_LOG}")
    print(f"⚡ Arquivo do MT5: {NOME_ARQUIVO_MT5}\n")
    
    await client.start()
    print("✅ Conectado com sucesso! Aguardando novas mensagens...")
    await client.run_until_disconnected()


if __name__ == "__main__":
    asyncio.run(main())