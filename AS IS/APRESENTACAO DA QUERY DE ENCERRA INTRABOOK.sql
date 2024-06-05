create procedure [dbo].[Encerra_Intrabooks]  as
declare @qtd_versionamento int declare @qtd_insert int 
declare @aux int ;
 
 -- Criação de tabelas com dados da tabela staging filtrando apenas os dados necessários para atender as necessidades do negócio
SELECT cast([Ano] as smallint) [Ano]
      ,case when ID_Ambiente = 'ENEL-TRADING' then (cast(concat(Codigo_Contrato,2) as int) * 10) else  (cast(concat(Codigo_Contrato,1) as int) * 10)	   end as [Codigo_Contrato]
      ,convert(date,(convert(datetime,substring(replace(data_ref,'/','-'),0,11),103)),23) [Data_ref]
      ,cast([Mes] as int) [Mes]
	  ,RTRIM(LTRIM([ID_Ambiente])) ID_Ambiente
INTO #TEMP_TRATADA  
FROM [Staging].[TEMP_Contratos_196] TEMP  
where TEMP.ID_Portfolio_Vendedor = 1 and (TEMP.id_parte <> TEMP.Id_contraparte)  and [Movimentacao] = 'Venda'  --  'Retail'  -- portifolio_comprador CFG 
-- Registros a Versionar
/*
Realiza comparação com tabela fato para identificar contratos que não aparecem mais na tabela staging, e 
portanto, precisam ser cancelados logicamente na tabela fato (campo dt_fim_vig é o responsável pelo 
controle desta informação. Quando um registro possui este campo cp, o valor '9999-12-31' definido 
significa que ele possui que aquela informação é a foto mais atual do dado. Quando o valor é diferente da 
data mencionada, o registro sofreu modificação naquele período e uma nova versão será disponibilizada na 
tabela ou o contrato foi cancelado e nenhuma nova versão será inserida na tabela fato.)
O bloco atual realiza o operador UNION ALL devido as regras de negócio em questão.
*/

/*
Problema 1 da query utilizada: utiliza o caracter asterico para retornar todos os dados da tabela fato 
que possui 256 campos. Para que as regras de negócio sejam atendidas neste caso, precisaremos apenas das colunas
xxxxxx, portanto, o uso do asterico é desnecessário e ainda provaca uma sobrecarga na leitura dos dados.
*/

SELECT FT.*
INTO #Contrato_Encerra 
FROM dbo.Fato_Contratos_196 FT
where FT.[CENARIO] = 'ATUAL' And FT.[DT_FIM_VIG] = '9999-12-31' AND ft.nome_contrato like '__INTRABOOK__%'
and not exists (select 1 from #TEMP_TRATADA TEMP 
					WHERE  isnull(FT.[Ano],0) = isnull(TEMP.[Ano],0)and isnull(FT.[Codigo_Contrato_Original_Intrabook],0) = 					isnull(TEMP.[Codigo_Contrato],0)and
					isnull(FT.[Mes],0) = isnull(TEMP.[Mes],0) and isnull(FT.[ID_Ambiente],0) = isnull(TEMP.[ID_Ambiente],0)) 
Union all/*
O operador distinct deve ser utilizado com muita cautela, tendo em vista o esforço computacional necessário para 
realizar sua operação. Novamente, é realizado o uso do asterico para realizar o distinct de uma tabela com 256 campos 
o que tende a gerar lentidão para está consulta.
*/
SELECT tab_i.*
FROM
(select distinct * from Fato_Contratos_196
where [CENARIO] = 'ATUAL' And [DT_FIM_VIG] = '9999-12-31' AND nome_contrato like '__INTRABOOK__%') tab_i
left join
(select distinct Codigo_Contrato, data_fechamento, Nome_contrato from Fato_Contratos_196
where [CENARIO] = 'ATUAL' And [DT_FIM_VIG] = '9999-12-31' and Id_parte <> Id_contraparte) tab_c
on tab_c.Codigo_Contrato = tab_i.Codigo_Contrato_Original_Intrabook
where tab_c.Data_fechamento <> tab_i.Data_fechamento; 
set @qtd_versionamento = (select count(*) from #Contrato_Encerra ) ;

if @qtd_versionamento > 0   
-- Fecha vigência na Fato antes de inserir novos dados/*
Como a tabela possui filtro no campo Dt_Fim_Vig e a quantidade de registros encerrados é normalmente bem pequena
esse update nã apresenta nenhum problema de execução
*/
	update Fato_Contratos_196
	set DT_Fim_Vig = CAST(getdate() AS DATE) --(select max(DATA_REF) from #Contrato_Encerra)
	from Fato_Contratos_196 FT
	WHERE FT.[CENARIO] = 'ATUAL' And FT.[DT_FIM_VIG] = '9999-12-31' 
	AND EXISTS (SELECT 1 FROM #Contrato_Encerra  V WHERE v.[Ano] = FT.Ano AND V.[Codigo_Contrato] = FT.[Codigo_Contrato]
	AND V.[Mes] = FT.[Mes] 	AND V.[ID_Ambiente] = FT.[ID_Ambiente] );/*
Insere dados na tabela dimensão de contratos encerrados

A quantidade de registros inseridos diariamente é muito pequena. Portanto, é outro bloco de código que não
apresenta problema de execução.
*/
INSERT INTO [dbo].[Fato_Contratos_196_Encerrados]
           ([Ano]
           ,[Codigo_Contrato]
           ,[Data_ref]
           ,[Mes]
           ,[ID_Ambiente]
		   ,[nome_contrato])
SELECT [Ano]
      ,[Codigo_Contrato]
       ,[Data_ref]
      ,[Mes]
      ,[ID_Ambiente]
	  ,[nome_contrato]
 FROM #Contrato_Encerra TEMP 