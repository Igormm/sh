Скрипт за один вызов показывает:
- где находится исполняемый файл (все варианты из `$PATH`);
- алиасы, функции и builtin-варианты;
- man-страницы, исходники, документацию;
- файлы с таким именем по всей файловой системе;
- из какого пакета установлена команда (DEB/RPM);
- права, дату, тип и MD5-сумму бинарника;
- связанные systemd-юниты;
- упоминания в журнале за последнюю неделю;
- все случаи запуска команды из истории shell;
- строки в `/var/log/*.log`.

При этом **root не требуется** — скрипт автоматически пропускает недоступные файлы.

## Установка

```bash
wget https://raw.githubusercontent.com/YOU/trace-cmd/main/trace-cmd.sh
chmod +x trace-cmd.sh
sudo mv trace-cmd.sh /usr/local/bin/trace-cmd   # опционально
```

### resolution-changer00

### resolution-changer01

### resolution-changer02