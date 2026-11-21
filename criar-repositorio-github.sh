#!/bin/bash
# Script de inicializacao automatica do projeto blindado para GitHub (Next.js + Supabase SSR)
# Como usar:
# 1. Crie uma pasta vazia no seu computador
# 2. Coloque este arquivo dentro dela
# 3. Abra o terminal na pasta e rode: bash criar-repositorio-github.sh

echo "Criando estrutura de pastas do projeto..."
mkdir -p supabase/migrations
mkdir -p src/lib/supabase
mkdir -p src/app/login
mkdir -p src/app/app
mkdir -p src/app/admin
mkdir -p src/app/api/admin/banir
mkdir -p src/app/api/mensagens

echo "Gerando .gitignore..."
cat << 'EOF' > .gitignore
node_modules
.next
.env
.env*.local
.DS_Store
*.log
EOF

echo "Gerando .env.example..."
cat << 'EOF' > .env.example
NEXT_PUBLIC_SUPABASE_URL=https://SEU-PROJETO.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=SUA_CHAVE_PUBLICA_ANON
EOF

echo "Gerando package.json..."
cat << 'EOF' > package.json
{
  "name": "rede-social-chat-blindada",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "@supabase/ssr": "^0.5.2",
    "@supabase/supabase-js": "^2.47.10",
    "next": "^14.2.18",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "zod": "^3.24.1"
  },
  "devDependencies": {
    "@types/node": "^20.17.9",
    "@types/react": "^18.3.12",
    "@types/react-dom": "^18.3.1",
    "autoprefixer": "^10.4.20",
    "postcss": "^8.4.49",
    "tailwindcss": "^3.4.15",
    "typescript": "^5.7.2"
  }
}
EOF

echo "Gerando tsconfig.json..."
cat << 'EOF' > tsconfig.json
{
  "compilerOptions": {
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
EOF

echo "Gerando next.config.mjs com Headers de Seguranca..."
cat << 'EOF' > next.config.mjs
/** @type {import('next').NextConfig} */
const nextConfig = {
  poweredByHeader: false,
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains; preload' },
          { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' }
        ],
      },
    ];
  },
};

export default nextConfig;
EOF

echo "Gerando schema SQL blindado (RLS + Triggers)..."
cat << 'EOF' > supabase/migrations/001_schema_blindado.sql
-- Habilita extensao UUID
create extension if not exists "uuid-ossp";

-- 1. Tabela de Perfis
create table public.perfis (
  id uuid references auth.users on delete cascade primary key,
  nome text not null check (char_length(nome) between 2 and 60),
  idade int not null check (idade >= 18 and idade <= 120),
  bio text check (char_length(bio) <= 300),
  foto_url text,
  role text not null default 'user' check (role in ('user', 'admin')),
  status text not null default 'ativo' check (status in ('ativo', 'banido')),
  criado_em timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 2. Tabela de Conversas
create table public.conversas (
  id uuid default uuid_generate_v4() primary key,
  usuario_1 uuid references public.perfis(id) on delete cascade not null,
  usuario_2 uuid references public.perfis(id) on delete cascade not null,
  criado_em timestamp with time zone default timezone('utc'::text, now()) not null,
  constraint usuarios_diferentes check (usuario_1 <> usuario_2)
);

-- 3. Tabela de Mensagens
create table public.mensagens (
  id uuid default uuid_generate_v4() primary key,
  conversa_id uuid references public.conversas(id) on delete cascade not null,
  remetente_id uuid references public.perfis(id) on delete cascade not null,
  conteudo text not null check (char_length(trim(conteudo)) between 1 and 1000),
  enviada_em timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 4. Tabela de Denuncias
create table public.denuncias (
  id uuid default uuid_generate_v4() primary key,
  denunciante_id uuid references public.perfis(id) on delete cascade not null,
  denunciado_id uuid references public.perfis(id) on delete cascade not null,
  motivo text not null check (char_length(trim(motivo)) between 5 and 500),
  resolvido boolean default false not null,
  criado_em timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 5. Tabela de Auditoria Administrativa
create table public.logs_auditoria (
  id uuid default uuid_generate_v4() primary key,
  admin_id uuid references public.perfis(id) not null,
  acao text not null,
  alvo_id uuid,
  detalhes jsonb,
  criado_em timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Ativar Realtime apenas nas mensagens
alter publication supabase_realtime add table public.mensagens;

-- ==========================================
-- TRAVA ANTI-ESCALADA DE PRIVILEGIOS (TRIGGER)
-- ==========================================
create or replace function public.proteger_campos_criticos_perfil()
returns trigger as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.role is distinct from old.role then
      raise exception 'Acesso negado: alteracao de cargo nao permitida via API.';
    end if;
    if new.status is distinct from old.status then
      raise exception 'Acesso negado: alteracao de status nao permitida via API.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trigger_proteger_perfil
  before update on public.perfis
  for each row execute function public.proteger_campos_criticos_perfil();

-- Funcao auxiliar para verificar admin
create or replace function public.is_admin()
returns boolean as $$
  select exists (
    select 1 from public.perfis
    where id = auth.uid() and role = 'admin' and status = 'ativo'
  );
$$ language sql security definer stable;

-- ==========================================
-- POLITICAS DE SEGURANCA (ROW LEVEL SECURITY)
-- ==========================================
alter table public.perfis enable row level security;
alter table public.conversas enable row level security;
alter table public.mensagens enable row level security;
alter table public.denuncias enable row level security;
alter table public.logs_auditoria enable row level security;

-- Perfis
create policy "Usuarios ativos veem perfis ativos ou admin ve todos"
  on public.perfis for select
  using (
    (status = 'ativo' and exists (select 1 from public.perfis p where p.id = auth.uid() and p.status = 'ativo'))
    or public.is_admin()
  );

create policy "Usuario cria proprio perfil como user ativo"
  on public.perfis for insert
  with check (auth.uid() = id and role = 'user' and status = 'ativo');

create policy "Usuario edita proprio perfil ou admin edita qualquer"
  on public.perfis for update
  using (auth.uid() = id or public.is_admin());

-- Conversas
create policy "Participantes ou admin veem conversas"
  on public.conversas for select
  using (auth.uid() = usuario_1 or auth.uid() = usuario_2 or public.is_admin());

create policy "Usuarios ativos criam conversas"
  on public.conversas for insert
  with check (
    (auth.uid() = usuario_1 or auth.uid() = usuario_2)
    and exists (select 1 from public.perfis where id = auth.uid() and status = 'ativo')
  );

-- Mensagens
create policy "Apenas participantes leem mensagens"
  on public.mensagens for select
  using (
    exists (
      select 1 from public.conversas c
      where c.id = conversa_id and (c.usuario_1 = auth.uid() or c.usuario_2 = auth.uid())
    )
  );

create policy "Apenas participantes ativos enviam mensagens"
  on public.mensagens for insert
  with check (
    auth.uid() = remetente_id
    and exists (select 1 from public.perfis where id = auth.uid() and status = 'ativo')
    and exists (
      select 1 from public.conversas c
      where c.id = conversa_id and (c.usuario_1 = auth.uid() or c.usuario_2 = auth.uid())
    )
  );

-- Denuncias
create policy "Usuario ativo cria denuncia"
  on public.denuncias for insert
  with check (
    auth.uid() = denunciante_id
    and exists (select 1 from public.perfis where id = auth.uid() and status = 'ativo')
  );

create policy "Apenas admin le e resolve denuncias"
  on public.denuncias for all
  using (public.is_admin());

-- Auditoria
create policy "Apenas admin insere e consulta auditoria"
  on public.logs_auditoria for all
  using (public.is_admin());
EOF

echo "Gerando clientes Supabase SSR..."
cat << 'EOF' > src/lib/supabase/client.ts
import { createBrowserClient } from '@supabase/ssr';

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
EOF

cat << 'EOF' > src/lib/supabase/server.ts
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // Ignorado em Server Components
          }
        },
      },
    }
  );
}
EOF

echo "Gerando src/middleware.ts (Guardiao de Rotas)..."
cat << 'EOF' > src/middleware.ts
import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const { data: { user } } = await supabase.auth.getUser();
  const pathname = request.nextUrl.pathname;

  if (!user && (pathname.startsWith('/app') || pathname.startsWith('/admin'))) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  if (user) {
    const { data: perfil } = await supabase
      .from('perfis')
      .select('role, status')
      .eq('id', user.id)
      .single();

    if (perfil?.status === 'banido') {
      await supabase.auth.signOut();
      return NextResponse.redirect(new URL('/login?erro=conta_suspensa', request.url));
    }

    if (pathname.startsWith('/admin') && perfil?.role !== 'admin') {
      return NextResponse.redirect(new URL('/app', request.url));
    }

    if (pathname === '/login') {
      const destino = perfil?.role === 'admin' ? '/admin' : '/app';
      return NextResponse.redirect(new URL(destino, request.url));
    }
  }

  return supabaseResponse;
}

export const config = {
  matcher: ['/app/:path*', '/admin/:path*', '/login'],
};
EOF

echo "Gerando API Route segura de Banimento (/api/admin/banir)..."
cat << 'EOF' > src/app/api/admin/banir/route.ts
import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { z } from 'zod';

const BanirSchema = z.object({
  usuarioId: z.string().uuid('ID de usuario invalido'),
  motivo: z.string().min(5, 'Motivo muito curto').max(300),
});

export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ erro: 'Nao autenticado' }, { status: 401 });
    }

    const { data: adminPerfil } = await supabase
      .from('perfis')
      .select('role, status')
      .eq('id', user.id)
      .single();

    if (adminPerfil?.role !== 'admin' || adminPerfil?.status !== 'ativo') {
      return NextResponse.json({ erro: 'Acesso negado' }, { status: 403 });
    }

    const body = await request.json();
    const validacao = BanirSchema.safeParse(body);

    if (!validacao.success) {
      return NextResponse.json({ erro: 'Dados invalidos' }, { status: 400 });
    }

    const { usuarioId, motivo } = validacao.data;

    if (usuarioId === user.id) {
      return NextResponse.json({ erro: 'Nao e possivel banir a propria conta' }, { status: 400 });
    }

    const { error: updateError } = await supabase
      .from('perfis')
      .update({ status: 'banido' })
      .eq('id', usuarioId);

    if (updateError) {
      return NextResponse.json({ erro: 'Falha ao banir usuario' }, { status: 500 });
    }

    await supabase.from('logs_auditoria').insert({
      admin_id: user.id,
      acao: 'BANIR_USUARIO',
      alvo_id: usuarioId,
      detalhes: { motivo },
    });

    return NextResponse.json({ sucesso: true });
  } catch {
    return NextResponse.json({ erro: 'Erro interno no servidor' }, { status: 500 });
  }
}
EOF

echo "Gerando Pagina Inicial, Login, App e Painel Admin..."
cat << 'EOF' > src/app/page.tsx
import Link from 'next/link';

export default function Home() {
  return (
    <main className="min-h-screen flex flex-col items-center justify-center bg-slate-950 text-white p-6 text-center">
      <h1 className="text-4xl font-bold mb-4">Rede Social de Relacionamentos</h1>
      <p className="text-slate-400 max-w-md mb-8">
        Plataforma segura com chat em tempo real e moderacao ativa.
      </p>
      <Link
        href="/login"
        className="bg-rose-600 hover:bg-rose-700 text-white font-semibold px-6 py-3 rounded-lg transition"
      >
        Acessar Plataforma
      </Link>
    </main>
  );
}
EOF

cat << 'EOF' > src/app/login/page.tsx
'use client';

import { useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [erro, setErro] = useState('');
  const [carregando, setCarregando] = useState(false);
  const router = useRouter();
  const supabase = createClient();

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    setErro('');
    setCarregando(true);

    const { data, error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });

    if (error || !data.user) {
      setErro('Credenciais invalidas. Verifique e-mail e senha.');
      setCarregando(false);
      return;
    }

    const { data: perfil } = await supabase
      .from('perfis')
      .select('role, status')
      .eq('id', data.user.id)
      .single();

    if (perfil?.status === 'banido') {
      await supabase.auth.signOut();
      setErro('Esta conta foi suspensa por violar os termos de uso.');
      setCarregando(false);
      return;
    }

    router.push(perfil?.role === 'admin' ? '/admin' : '/app');
    router.refresh();
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-950 p-4">
      <form onSubmit={handleLogin} className="bg-slate-900 border border-slate-800 p-8 rounded-xl w-full max-w-md space-y-4 text-white">
        <h2 className="text-2xl font-bold text-center">Entrar na Conta</h2>
        {erro && <p className="bg-red-950 border border-red-700 text-red-200 text-sm p-3 rounded">{erro}</p>}
        <div>
          <label className="block text-sm text-slate-400 mb-1">E-mail</label>
          <input
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full p-2.5 rounded bg-slate-800 border border-slate-700 focus:outline-none focus:border-rose-500"
          />
        </div>
        <div>
          <label className="block text-sm text-slate-400 mb-1">Senha</label>
          <input
            type="password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full p-2.5 rounded bg-slate-800 border border-slate-700 focus:outline-none focus:border-rose-500"
          />
        </div>
        <button
          type="submit"
          disabled={carregando}
          className="w-full bg-rose-600 hover:bg-rose-700 py-2.5 rounded font-semibold transition disabled:opacity-50"
        >
          {carregando ? 'Verificando...' : 'Entrar'}
        </button>
      </form>
    </div>
  );
}
EOF

cat << 'EOF' > src/app/app/page.tsx
import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';

export default async function UserChatApp() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) redirect('/login');

  const { data: perfis } = await supabase
    .from('perfis')
    .select('id, nome, idade, bio')
    .neq('id', user.id)
    .eq('status', 'ativo')
    .limit(20);

  return (
    <div className="min-h-screen bg-slate-950 text-white p-6">
      <header className="max-w-4xl mx-auto flex justify-between items-center border-b border-slate-800 pb-4 mb-6">
        <h1 className="text-xl font-bold text-rose-500">Area do Usuario - Chat</h1>
        <span className="text-xs text-slate-400">{user.email}</span>
      </header>

      <main className="max-w-4xl mx-auto">
        <h2 className="text-lg font-semibold mb-4">Pessoas Disponiveis para Conversar</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {perfis?.map((p) => (
            <div key={p.id} className="bg-slate-900 border border-slate-800 p-4 rounded-lg">
              <h3 className="font-bold text-lg">{p.nome}, {p.idade}</h3>
              <p className="text-sm text-slate-400 mt-1">{p.bio || 'Sem descricao.'}</p>
            </div>
          ))}
          {(!perfis || perfis.length === 0) && (
            <p className="text-slate-500 text-sm">Nenhum outro perfil ativo encontrado no momento.</p>
          )}
        </div>
      </main>
    </div>
  );
}
EOF

cat << 'EOF' > src/app/admin/page.tsx
import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';

export default async function AdminDashboard() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) redirect('/login');

  const { data: usuarios } = await supabase
    .from('perfis')
    .select('id, nome, idade, role, status, criado_em')
    .order('criado_em', { ascending: false });

  const { data: denuncias } = await supabase
    .from('denuncias')
    .select('*')
    .eq('resolvido', false);

  return (
    <div className="min-h-screen bg-slate-950 text-white p-6">
      <header className="max-w-5xl mx-auto flex justify-between items-center border-b border-slate-800 pb-4 mb-6">
        <h1 className="text-xl font-bold text-amber-400">Painel do Administrador</h1>
        <span className="text-xs bg-amber-950 text-amber-300 px-3 py-1 rounded-full border border-amber-700">
          Acesso Restrito
        </span>
      </header>

      <main className="max-w-5xl mx-auto space-y-8">
        <section>
          <h2 className="text-lg font-semibold mb-3">Denuncias Pendentes ({denuncias?.length || 0})</h2>
          <div className="bg-slate-900 border border-slate-800 rounded-lg p-4 text-sm text-slate-400">
            {denuncias && denuncias.length > 0
              ? `${denuncias.length} denuncia(s) aguardando revisao.`
              : 'Nenhuma denuncia pendente.'}
          </div>
        </section>

        <section>
          <h2 className="text-lg font-semibold mb-3">Usuarios Cadastrados ({usuarios?.length || 0})</h2>
          <div className="overflow-x-auto bg-slate-900 border border-slate-800 rounded-lg">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-slate-800 text-slate-400">
                <tr>
                  <th className="p-3">Nome</th>
                  <th className="p-3">Idade</th>
                  <th className="p-3">Cargo</th>
                  <th className="p-3">Status</th>
                </tr>
              </thead>
              <tbody>
                {usuarios?.map((u) => (
                  <tr key={u.id} className="border-b border-slate-800/50">
                    <td className="p-3 font-medium">{u.nome}</td>
                    <td className="p-3">{u.idade}</td>
                    <td className="p-3">{u.role}</td>
                    <td className="p-3">
                      <span className={u.status === 'ativo' ? 'text-emerald-400' : 'text-red-400'}>
                        {u.status}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </main>
    </div>
  );
}
EOF

echo "Gerando README.md..."
cat << 'EOF' > README.md
# Rede Social de Relacionamentos (Arquitetura Blindada)

Projeto em **Next.js (App Router)** + **Supabase SSR** com autenticacao separada para **Usuarios** (`/app`) e **Administradores** (`/admin`), protecao contra escalada de privilegios via Triggers SQL e Row Level Security (RLS).

## Como colocar no ar

1. Instale as dependencias:
   ```bash
   npm install
   ```
2. Crie um projeto no Supabase e execute o arquivo `supabase/migrations/001_schema_blindado.sql` no **SQL Editor**.
3. Copie `.env.example` para `.env.local` e preencha suas chaves do Supabase.
4. Suba este repositorio para o GitHub e importe na **Vercel**.
5. Apos criar sua conta no site, altere sua coluna `role` para `'admin'` diretamente na tabela `perfis` no painel do Supabase.
EOF

echo "Instalando dependencias NPM (opcional, pode rodar npm install depois)..."
echo "Projeto completo gerado com sucesso! Pronto para git init e push no GitHub."
