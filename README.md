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
| `termos.html` | Termos de uso e política de privacidade (LGPD). |
| `og.jpg` | Imagem da prévia do link no WhatsApp, Instagram e LinkedIn. |
| `exemplo/diagnostico-ia-exemplo.pdf` | Laudo de exemplo do diagnóstico por IA, com marca d'água EXEMPLO. |
| `exemplo/laudo-vistoria-exemplo.pdf` | Laudo de exemplo de vistoria de entrada de locação. |

## Backend

Supabase, no mesmo projeto do Foster Calc (`fvsdlpnvqfvjdxmfgbjx`): uma conta vale para os dois produtos.

| Peça | O que faz |
|---|---|
| Tabela `vist_contas` | Plano de cada usuário (`teste`, `essencial`, `profissional`), validade e perfil profissional (logo, registro, assinatura). Só muda pelas funções abaixo. |
| Tabelas `vist_diagnosticos` e `vist_vistorias` | Histórico. Cada usuário só lê e apaga o que é dele (RLS). Criar exige plano ativo. |
| Tabela `vist_analises` | Registro de cada análise por IA, para o limite do plano. |
| `vist_status()` | Cria a conta com 7 dias de teste no primeiro acesso e devolve plano, validade e uso. |
| `vist_reservar_analise()` | Confere plano e limite antes de chamar a IA. |
| `vist_ativar_plano()` e `vist_cancelar_se()` | Chamadas só pelo webhook do Asaas. |
| `vist_salvar_perfil()` | Salva o perfil profissional na nuvem. |
| Função `vistoria-analisar` | Confere o login, reserva a análise, chama a IA da Groq e devolve a análise se a IA falhar. Código em `supabase/functions/vistoria-analisar`. Segredo: `GROQ_API_KEY`. |
| Função `asaas-webhook` | Central de pagamentos Foster (código no repositório do Foster Calc). Ativa os planos do VistorIA pelos valores R$ 49, 490, 89 e 890. |

### Planos

| Plano | Preço | Diagnósticos por IA |
|---|---|---|
| Teste grátis | 7 dias | 5 no total |
| Essencial | R$ 49/mês ou R$ 490/ano | 15 a cada 30 dias |
| Profissional | R$ 89/mês ou R$ 890/ano | 150 a cada 30 dias |

Vistorias completas não usam IA e não têm limite. Os links de pagamento ficam em `PLANOS_VIST`, no `index.html`. Enquanto um link estiver vazio, o botão abre o WhatsApp.

## Desenvolvedor

Wilson Foster · Foster Engenharia & Construção · Eng. Civil CREA-SP 5071894914
(24) 99209-6103 · comercial@fosterconstrucoes.com.br
