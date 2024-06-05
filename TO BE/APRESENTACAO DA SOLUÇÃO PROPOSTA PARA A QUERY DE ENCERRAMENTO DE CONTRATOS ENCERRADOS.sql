CREATE procedure [dbo].[Encerra_Intrabooks]  as

declare @qtd_versionamento int 
declare @qtd_insert int 
declare @aux int ;
 

 -- Criação de tabelas com dados da tabela staging filtrando apenas os dados necessários para atender as necessidades do negócio
SELECT cast([Ano] as smallint) [Ano]
       ,case when ID_Ambiente = 'TRADING' then (cast(concat(Codigo_Contrato,2) as int) * 10) else  (cast(concat(Codigo_Contrato,1) as int) * 10) 
	   end as [Codigo_Contrato]
      ,convert(date,(convert(datetime,substring(replace(data_ref,'/','-'),0,11),103)),23) [Data_ref]
      ,cast([Mes] as int) [Mes]
	  ,RTRIM(LTRIM([ID_Ambiente])) ID_Ambiente
INTO #TEMP_TRATADA  
FROM [Staging].TEMP_Contratos_196 TEMP  
where TEMP.ID_Portfolio_Vendedor = 1 and (TEMP.id_parte <> TEMP.Id_contraparte)  and [Movimentacao] = 'Venda'  --  'Retail'  -- portifolio_comprador CFG 


/*
Partindo do princípio que as demais queries farão relacionamentos entre a tabela fato e a tabela temporária
utilizando os campos Codigo_Contrato, Id_Ambiente, Ano, Mês foi criado um índice clusterizado na #TEMP_TRATADA com o objetivo de ordenar os dados fisicamente pelos
campos mencionados e otimizar as consultas posteriores
*/

CREATE CLUSTERED INDEX INC_CHAVE_JOIN_TEMP_TRATADA
ON #TEMP_TRATADA
(
	[Codigo_Contrato],
	[ID_Ambiente],
	[Ano],
	[Mes]
)

/*
Sabendo que a tabela fato será referenciada mais de uma vez, e que não tenho um índice de cobertura
que consiga isolar todos os campos que preciso, foi criada uma tabela temporária apenas os campos e números de registros
necessários para atender a regra de negócio, o objetivo é criar um objeto com a quantidade de páginas de dados bem menor
do que a tabela fato, o que consequentemente reduzirá bastante o tempo de execução para a leitura do objeto.
*/

SELECT
	   Codigo_Contrato
      ,Codigo_Contrato_Original_Intrabook
      ,[Data_ref]
	  ,[Ano]
      ,[Mes]
      ,[ID_Ambiente]
	  ,[nome_contrato]
	  ,Data_fechamento
	  , Id_parte
	  ,Id_contraparte
	  INTO #TEMP_CONTRATOS
	  from Fato_Contratos_196
where [DT_FIM_VIG] = '9999-12-31'


/*
Tal como na tabela #TEMP_TRATADA, o objetivo da criação de índice clusterizado para a tabela #TEMP_CONTRATOS
é otimizar a consulta no contexto que envolvem consultas a este objeto.
*/
CREATE CLUSTERED INDEX INC_CHAVE_JOIN_TEMP_TRATADA
ON #TEMP_CONTRATOS
(
	[Codigo_Contrato],
	[ID_Ambiente],
	[Ano],
	[Mes]
)


/*
Diferente da consulta anterior, os campos selecionados foram aqueles que realmente seriam necessários para atender os requisitos de negócios,
o que consequentemente diminui o tempo de leitura e a quantidade de memória necessário que o otimizar 
vai projetar para recuperar os dados. Ou seja, além de executar mais rapidamente, a query ainda exigirá menos recursos do servidor ao solicitar uma quantidade menor de memória 
para executar a query.Além disso, ao invés de utilizar a tabela fato para a comparação de contratos encerrados,
utiliza-se a tabela #TEMP_CONTRATOS que está otimizada para atender este caso.
*/
SELECT 
      FT.[Codigo_Contrato]
	  ,FT.[Ano]
      ,FT.[Data_ref]
      ,FT.[Mes]
      ,FT.[ID_Ambiente]
	  ,FT.[nome_contrato]	
INTO #Contrato_Encerra 
FROM #TEMP_CONTRATOS FT
where ft.nome_contrato like '__INTRABOOK__%'
and 
		not exists (select 1 from #TEMP_TRATADA TEMP 
					WHERE  isnull(FT.[Ano],0) = isnull(TEMP.[Ano],0)and isnull(FT.[Codigo_Contrato_Original_Intrabook],0) = isnull(TEMP.[Codigo_Contrato],0)and
					isnull(FT.[Mes],0) = isnull(TEMP.[Mes],0) and isnull(FT.[ID_Ambiente],0) = isnull(TEMP.[ID_Ambiente],0)) 


Union all
/*
Apesar do operador distinct não poder ser evitado nessa situação, utilizou apenas as colunas necessárias 
para atender as regras de negócios, além de realizar a comparação com a tabela otimizada para este situação
(#TEMP_CONTRATOS).
*/

SELECT 
	   tab_i.[Codigo_Contrato]
	  ,tab_i.[Ano]
      ,tab_i.[Data_ref]
      ,tab_i.[Mes]
      ,tab_i.[ID_Ambiente]
	  ,tab_i.[nome_contrato]
FROM
(select distinct 
	   
      Codigo_Contrato_Original_Intrabook
	  ,Codigo_Contrato
      ,[Data_ref]
	  ,[Ano]
      ,[Mes]
      ,[ID_Ambiente]
	  ,[nome_contrato]
	  ,Data_fechamento
	  from #TEMP_CONTRATOS
where  nome_contrato like '__INTRABOOK__%') tab_i
left join
(select distinct Codigo_Contrato, data_fechamento, Nome_contrato from #TEMP_CONTRATOS
where Id_parte <> Id_contraparte) tab_c
on tab_c.Codigo_Contrato = tab_i.Codigo_Contrato_Original_Intrabook
where tab_c.Data_fechamento <> tab_i.Data_fechamento; 



-- Fecha vigência na Fato antes de inserir novos dados/*
Como a tabela possui filtro no campo Dt_Fim_Vig e a quantidade de registros encerrados é normalmente bem pequena
esse update nã apresenta nenhum problema de execução
*/
	update Fato_Contratos_196
	set DT_Fim_Vig = CAST(getdate() AS DATE) --(select max(DATA_REF) from #Contrato_Encerra)
	from Fato_Contratos_196 FT
	WHERE FT.[CENARIO] = 'ATUAL' And FT.[DT_FIM_VIG] = '9999-12-31' 
	AND EXISTS (
	SELECT 1 FROM #Contrato_Encerra  V 
	WHERE isnull(FT.[Ano],0) = isnull(V.[Ano],0) AND 
	V.[Codigo_Contrato] = FT.[Codigo_Contrato]
	AND isnull(FT.[Mes],0) = isnull(V.[Mes],0) 	AND V.[ID_Ambiente] = FT.[ID_Ambiente]
	);

/*
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



DROP TABLE #Contrato_Encerra;
DROP TABLE #TEMP_CONTRATOS;
DROP TABLE #TEMP_TRATADA;

end

