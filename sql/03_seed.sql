-- Seed: 4 revendas fictícias (protegidas) + 60 dias de dados cada
insert into revendas(codigo,nome,cidade,uf,demo_base) values
('HRZ','Distribuidora Horizonte','Sorocaba','SP',true),
('VVD','Distribuidora Vale Verde','Juiz de Fora','MG',true),
('SAZ','Distribuidora Serra Azul','Chapecó','SC',true),
('LSL','Distribuidora Litoral Sul','Anápolis','GO',true);
select codigo, gerar_demo(id, 60) as mapas from revendas order by codigo;
