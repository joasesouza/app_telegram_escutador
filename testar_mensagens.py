from datetime import datetime
import os
from telethon import TelegramClient, events

# 1. Suas credenciais do Telegram
API_ID = 1234567  # Substitua pelo seu API ID
API_HASH = "seu_api_hash_aqui"  # Substitua pelo seu API Hash

SESSION_NAME = "sessao_telegram_vps"

# Generates a new unique file name for each execution based on start timestamp
timestamp_inicio = datetime.now().strftime("%Y%m%d_%H%M%S")
NOME_ARQUIVO_LOG = f"log_mensagens_{timestamp_inicio}.txt"

client = TelegramClient(SESSION_NAME, API_ID, API_HASH)


def salvar_em_log(texto_log: str):
    """Grava o texto no arquivo de log garantindo escrita imediata no disco."""
    with open(NOME_ARQUIVO_LOG, "a", encoding="utf-8") as file:
        file.write(texto_log + "\n")
        file.flush()  # Força a gravação imediata no disco (sem delay de cache)


@client.on(events.NewMessage)
async def monitorar_todas_mensagens(event):
    """Captura e grava no arquivo TXT toda e qualquer mensagem recebida."""
    texto = event.message.message

    if not texto:
        texto = "[Mensagem sem texto / Apenas mídia]"

    # Busca informações do chat/remetente
    try:
        chat = await event.get_chat()
        nome_chat = getattr(
            chat, "title", getattr(chat, "first_name", "Chat Desconhecido")
        )
    except Exception:
        nome_chat = "Chat Desconhecido"

    chat_id = event.chat_id
    hora_recebimento = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Monta a estrutura da mensagem para o log
    bloco_mensagem = (
        f"{'='*60}\n"
        f"⏰ Data/Hora: {hora_recebimento}\n"
        f"📌 Origem: {nome_chat}\n"
        f"🆔 Chat ID: {chat_id}\n"
        f"💬 Conteúdo:\n{texto}\n"
        f"{'='*60}\n"
    )

    # Grava no arquivo TXT
    salvar_em_log(bloco_mensagem)


async def main():
    mensagem_inicio = (
        f"🚀 Monitoramento iniciado. Registrando logs em: {NOME_ARQUIVO_LOG}\n"
    )
    print(mensagem_inicio)

    # Cria o arquivo e escreve o cabeçalho de inicialização
    salvar_em_log(
        f"--- INÍCIO DO REGISTRO: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ---"
    )

    await client.start()
    print("✅ Conectado com sucesso! Gravando novas mensagens no arquivo...")
    await client.run_until_disconnected()


if __name__ == "__main__":
    import asyncio

    asyncio.run(main())
