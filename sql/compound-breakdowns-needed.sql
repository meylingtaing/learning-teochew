select
    English.id english_id,
    English.word,
    Teochew.pengim,
    Teochew.chinese,
    English.hidden
from English
join Translation on Translation.english_id = English.id
join Teochew on Translation.teochew_id = Teochew.id
left join Compound on Compound.parent_teochew_id = Teochew.id
where length(Teochew.chinese) > 1 and Compound.id is null
    and English.id > 66
    and English.category_id != 2
order by English.id
limit 4;
