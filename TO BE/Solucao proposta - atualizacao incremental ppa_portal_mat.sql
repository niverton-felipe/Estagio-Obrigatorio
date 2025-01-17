CREATE PROCEDURE [Materializacoes].[P_Atualizar_Tabela_Materializada_Vba_Portfolio_Ppa_Portal] AS

/*
  Criação explícita de tabela temporária afim de gerar mais rapidamente os índices clusterizados e não clusterizados que ajudarão a acelerar
  os relacionamentos utilizados durante a consulta
*/

CREATE TABLE #portfolio_ppa_portal(
	[ID_Produto] [int] NULL,
	[Status] [varchar](50) NULL,
	[Valor_financeiro_atualizado] [decimal](18, 6) NULL,
	[Valor_Ressarcimento] [decimal](18, 6) NULL,
	[Intercompany] [int] NOT NULL,
	[ID_Contraparte] [int] NULL,
	[ID_Fonte] [int] NULL,
	[ID_Submercado] [int] NULL,
	[Ano] [smallint] NULL,
	[Mes] [tinyint] NULL,
	[DT_Ini_Vig] [date] NULL,
	[DT_Fim_Vig] [date] NULL,
	[Data_Ref] [date] NULL,
	[Data_Criacao] [datetime2](0) NULL,
	[data_fechamento] [datetime2](0) NULL,
	[Data_publicacao] [datetime2](0) NULL,
	[ID_UF] [int] NULL,
	[Contrato_Faturado] [int] NOT NULL,
	[Nr_contrato_vinculado] [varchar](50) NULL,
	[FlexibilidadeMensalMax] [decimal](18, 6) NULL,
	[FlexibilidadeMensalMin] [decimal](18, 6) NULL,
	[Valor_Financeiro_Realizado] [decimal](18, 6) NULL,
	[Suprimento_inicio] [date] NULL,
	[Suprimento_termino] [date] NULL,
	[Quant_Contratada] [decimal](18, 6) NULL,
	[Preco_base] [decimal](18, 6) NULL,
	[ID_Tipo_Contrato] [int] NULL,
	[ID_Parte] [int] NULL,
	[Tipo_Contrato] [varchar](50) NULL,
	[Horas] [int] NULL,
	[Data_Rel] [datetime] NULL,
	[Cenario] [varchar](50) NULL,
	[Empresa_Nivel5] [nvarchar](255) NULL,
	[Empresa_Nivel4] [nvarchar](255) NULL,
	[Empresa_Nivel3] [nvarchar](255) NULL,
	[Empresa_Nivel2] [nvarchar](255) NULL,
	[Empresa_Nivel1] [nvarchar](255) NULL,
	[Movimentacao] [varchar](20) NULL,
	[Ramo_Atividade] [varchar](500) NULL,
	[ID_Portfolio] [int] NULL,
	[Portfolio] [varchar](50) NULL,
	--[ID_Contratos_196] [int] PRIMARY KEY,
	[ID_Contratos_196] [int],
	[ID_Contratos_196_Persist] [int] NULL,
	[Nome_Contrato] [varchar](250) NULL,
	[Codigo_WBC] [int] NULL,
	[Fonte] [varchar](100) NULL,
	[Submercado] [varchar](50) NULL,
	[Contraparte] [varchar](110) NULL,
	[Ambiente] [varchar](3) NOT NULL,
	[Segmento_Mercado] [varchar](50) NULL,
	[Regra_Preco] [varchar](50) NULL,
	[Form_Agio] [varchar](255) NULL,
	[Quantidade_MWh] [decimal](18, 6) NULL,
	[Quantidade_MWm] [decimal](29, 17) NULL,
	[Intrabook] [int] NOT NULL,
	[epai] [bit] NOT NULL,
	[Contraparte_Estado] [varchar](2) NULL,
	[Contrato_legado] [varchar](1500) NULL
)

CREATE NONCLUSTERED INDEX IX_ID_Contratos_196_Persist_Dt_Fim_Vig
ON #portfolio_ppa_portal ([ID_Contratos_196_Persist], [DT_Fim_Vig])

-- Seleciona apenas os dados que não estão na tabela destino
INSERT INTO #portfolio_ppa_portal

SELECT *
FROM [dbo].[vba_portfolio_ppa_portal_performance] t_view
WHERE NOT EXISTS (SELECT 1 FROM vw_portfolio_ppa_portal_mat t_mat WHERE t_mat.ID_Contratos_196  = t_view.ID_Contratos_196)

-- Seleciona dados da tabela destino que terão a vigência encerrada
SELECT
t_mat.ID_Contratos_196

INTO #TEMP_REGISTROS_MODIFICADOS
FROM dbo.vw_portfolio_ppa_portal_mat AS t_mat

-- Join nos dados de vigencia aberta com o mesmo ID_PERSIST 
INNER JOIN #portfolio_ppa_portal AS t_view

ON t_mat.ID_Contratos_196_Persist = t_view.ID_Contratos_196_Persist 

AND t_view.DT_Fim_Vig = '9999-12-31'
AND t_mat.DT_Fim_Vig = '9999-12-31'
-- Encerra apenas os dados que tenham modificações (diferentes IDs únicos)
WHERE t_view.ID_Contratos_196  <> t_mat.ID_Contratos_196


-- Encerra a vigência dos dados que tenham versão mais recente
--Pegando como referência a dt_fim_vig da Fato_contratos_196 afim de garantir que dados
--serão terão informação consistente em relação à data fim vigência 
UPDATE t_mat

SET t_mat.DT_Fim_Vig = origem.Dt_Fim_Vig
FROM dbo.vw_portfolio_ppa_portal_mat AS t_mat

-- Join nos dados que foram modificados
INNER JOIN #TEMP_REGISTROS_MODIFICADOS AS t_view
ON t_mat.ID_Contratos_196  = t_view.ID_Contratos_196  

--join nos dados na fonte primária dos dados para pegar a data fim vigencia mais confiável
INNER JOIN [dbo].[Fato_contratos_196] origem
ON origem.ID_Contratos_196  = ROUND((t_mat.ID_Contratos_196) / 10, 0)


--Seleciona dados da view ppa_portal que estão com a vigência fechada
SELECT 
A.ID_Contratos_196,
A.DT_Fim_Vig,
A.Cenario
INTO #TEMP_PPA_PORTAL
FROM [dbo].[vba_portfolio_ppa_portal_performance] A
WHERE DT_Fim_Vig <> '9999-12-31'


CREATE CLUSTERED INDEX IC_ID_Contratos_196
ON #TEMP_PPA_PORTAL (ID_Contratos_196) 

--Altera a data de vigência da tabela materializada de contratos que foram encerrados na VBA contratos e não receberam nova vigência. 
--Na versão anterior da procedure, os dados continuavam com vigência aberta na tabela materializada e retornava registros com informações inconsistentes nas extrações de balanço.
UPDATE A
SET DT_Fim_Vig = B.DT_Fim_Vig
FROM dbo.vw_portfolio_ppa_portal_mat A
INNER JOIN #TEMP_PPA_PORTAL B
ON A.ID_Contratos_196  = B.ID_Contratos_196
AND A.Cenario = B.Cenario
WHERE A.DT_Fim_Vig <> B.DT_Fim_Vig

-- Insere os dados cujo ID único não estão na tabela materializada
INSERT INTO vba_portfolio_ppa_portal_ 

SELECT *
FROM #portfolio_ppa_portal


DROP TABLE #portfolio_ppa_portal;