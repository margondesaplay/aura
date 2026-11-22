# AURA — Rede social simples

**Identidade visual:** o nome da rede é **AURA**, com uma **pimenta vermelha como logomarca** e paleta em **vermelho, preto e cinza**. O símbolo vetorial da pimenta já está incluído no cabeçalho e na tela de entrada.

Projeto inicial de rede social com feed compartilhado, cadastro/login por e-mail, confirmação por código e mensagens privadas. Front-end estático (HTML/CSS/JavaScript) e backend/banco no Supabase. Pode ser publicado no GitHub Pages.

## O que já vem funcionando

- Cadastro e login individual por e-mail e senha.
- Confirmação de cadastro por e-mail (OTP/código, conforme configuração do Supabase).
- Feed de publicações visível a usuários autenticados.
- Perfil com nome de exibição e biografia.
- Conversas privadas entre usuários autenticados.
- Políticas de segurança no banco (RLS): mensagens só podem ser lidas pelo remetente e destinatário.
- Layout responsivo para celular e computador.

> Gmail: o usuário pode cadastrar seu endereço `@gmail.com` e receber nele a confirmação. O envio é feito pelo serviço de autenticação do Supabase, não pelo navegador. Para entrega confiável em produção, configure um provedor SMTP no Supabase. Não coloque senha do Gmail nem chave secreta no código do site.

## 1. Criar o backend gratuito

1. Entre em https://supabase.com e crie uma conta.
2. Crie um projeto chamado `aura-social` e guarde a senha do banco.
3. No painel, abra **SQL Editor → New query**.
4. Copie todo o conteúdo de `supabase/schema.sql`, cole no editor e clique em **Run**.
5. Abra **Project Settings → API** e copie:
   - Project URL
   - `anon` / `publishable` key (chave pública do projeto)

## 2. Configurar o site

Abra `src/app.js` e substitua as duas linhas:

```js
const SUPABASE_URL = "COLE_A_URL_DO_SEU_PROJETO";
const SUPABASE_ANON_KEY = "COLE_A_CHAVE_ANON_PUBLIC";
```

pelos valores do seu projeto. A chave `anon`/publishable é própria para uso no navegador quando as políticas RLS estão ativas. **Nunca** coloque `service_role`, senha do banco ou chave SMTP no JavaScript.

## 3. Ativar confirmação por código no e-mail

No painel Supabase:

1. Entre em **Authentication → Providers → Email** e deixe Email habilitado.
2. Em **Authentication → URL Configuration**, adicione o endereço do seu site em **Site URL** e **Redirect URLs**. Para teste local, inclua `http://localhost:8000/**`; para GitHub Pages, inclua `https://SEU-USUARIO.github.io/**`.
3. Em **Authentication → Email Templates**, configure o template de confirmação para mostrar um OTP. O template pode usar `{{ .Token }}`. O formulário deste projeto valida o código usando o tipo `signup`.
4. Para que as mensagens cheguem com mais confiabilidade ao Gmail, configure SMTP próprio em **Project Settings → Authentication → SMTP Settings**. Use um serviço SMTP transacional. Se optar pelo Gmail/Google Workspace, use senha de app quando disponível e respeite os limites do Google. Nunca publique credenciais SMTP no repositório.

O serviço padrão do Supabase pode ter limites de envio e não é indicado para produção. O recebimento em Gmail depende da configuração do provedor e da entrega do e-mail.

## 4. Testar no computador (Windows)

É necessário servir os arquivos por HTTP (não abrir `index.html` diretamente).

1. Instale o Node.js LTS: https://nodejs.org
2. Extraia a pasta `aura-social`.
3. Abra o Prompt de Comando dentro dela.
4. Execute:

```bash
npx serve .
```

5. Abra o endereço local informado no terminal (normalmente `http://localhost:3000`).

Alternativa com Python instalado:

```bash
python -m http.server 8000
```

e acesse `http://localhost:8000`.

## 5. Publicar no GitHub Pages

1. Crie um repositório no GitHub, por exemplo `aura-social`.
2. Envie todos os arquivos e pastas deste projeto para a raiz do repositório.
3. Abra **Settings → Pages**.
4. Em **Build and deployment**, escolha **Deploy from a branch**, branch `main`, pasta `/ (root)`, e salve.
5. Aguarde a publicação. Seu endereço será parecido com `https://SEU-USUARIO.github.io/aura-social/`.
6. Volte ao Supabase e inclua esse endereço em **Authentication → URL Configuration → Redirect URLs**.

## Estrutura

```text
aura-social/
├── index.html
├── README.md
├── .nojekyll
├── .gitignore
├── src/
│   ├── app.js
│   └── style.css
└── supabase/
    └── schema.sql
```

## Observações importantes

- O projeto usa Supabase para autenticação, banco e segurança; GitHub Pages hospeda apenas o front-end.
- O site não é um serviço de e-mail: o Supabase/SMTP envia o código ao endereço cadastrado.
- O feed e os perfis ficam disponíveis para usuários autenticados. As mensagens privadas têm políticas RLS no banco.
- Esta é uma primeira versão funcional, não uma plataforma corporativa: antes de abrir ao público, adicione moderação, denúncia/bloqueio, limites anti-spam, recuperação de senha, paginação e monitoramento.
- A biblioteca Supabase JS é carregada por CDN, portanto o navegador precisa de internet.
