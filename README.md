# VistorIA

Diagnóstico de patologias construtivas por IA e laudo de vistoria, direto do celular.

Site: https://fosterfcs.github.io/vistoria/

## O que faz

- **Diagnóstico por foto:** a IA avalia a foto (trinca, fissura, infiltração, mofo, corrosão etc.) e devolve:
  - tipo da manifestação;
  - risco (baixo, atenção, prioridade ou crítico);
  - hipóteses de causa;
  - se o elemento é estrutural;
  - investigações recomendadas;
  - norma de referência.
- **Vistoria completa:** registro cômodo por cômodo e item por item, com estado, foto e observação. Serve para:
  - locação (entrada e saída);
  - obra nova;
  - reforma;
  - avaliação geral.
- **Assinatura na tela:** do vistoriador e do cliente, com data e hora.
- **PDF com a marca do profissional:** logo, nome, CREA/CAU, telefone e e-mail. O PDF é enviado pelo WhatsApp.
- **Histórico na nuvem:** com busca.

Todo relatório informa que se trata de uma avaliação técnica **preliminar** assistida por IA, que não substitui a vistoria presencial nem o laudo com ART/RRT.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `index.html` | O aplicativo inteiro e a página de apresentação pública (mostrada a quem não está logado). |
| `manifest.json`, `icon-192.png`, `icon-512.png` | Instalação na tela inicial do celular. |
| `og.jpg` | Imagem da prévia do link no WhatsApp, Instagram e LinkedIn. |
| `exemplo/diagnostico-ia-exemplo.pdf` | Laudo de exemplo do diagnóstico por IA, com marca d'água EXEMPLO. |
| `exemplo/laudo-vistoria-exemplo.pdf` | Laudo de exemplo de vistoria de entrada de locação. |

## Backend

O app conversa com um Cloudflare Worker em `https://vistoria-worker.fosterconstrutora.workers.dev`, com banco D1 e IA de visão da Groq. O código do Worker **não está neste repositório**.

Rotas usadas pelo app:

| Rota | Métodos |
|---|---|
| `/api/login`, `/api/logout` | POST |
| `/api/me` | GET |
| `/api/usuarios` | GET, POST |
| `/api/usuarios/:id` | DELETE |
| `/api/diagnosticos` e `/api/diagnosticos/:id` | GET, POST, DELETE |
| `/api/vistorias` e `/api/vistorias/:id` | GET, POST, DELETE |
| `/api/analisar` | POST, com a foto em base64 |

O login guarda o token em `localStorage` (`vst_session`) e envia `Authorization: Bearer`. O perfil profissional (logo, registro, assinatura) fica no próprio aparelho, em `vst_perfil_<email>`.

### Contas e acesso

- Não existe cadastro aberto. O acesso é criado pelo administrador no menu **Usuários**.
- O menu Usuários aparece só para a conta mais antiga, que é a do administrador.
- A proteção real precisa estar no Worker:
  - só o administrador pode criar e excluir usuários;
  - cada usuário só vê os próprios diagnósticos e vistorias.

## Desenvolvedor

Wilson Foster · Foster Engenharia & Construção · Eng. Civil CREA-SP 5071894914
(24) 99209-6103 · comercial@fosterconstrucoes.com.br
