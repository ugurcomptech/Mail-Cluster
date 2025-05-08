# 📧 Mail Cluster Mimarisi

Bu projede yüksek erişilebilirlik ve veri bütünlüğü sağlayan bir mail cluster sistemi kurdum. Yapı aşağıdaki bileşenlerden oluşmaktadır:

## 🔁 Yük Dengeleme (Web Arayüzü)

Web tabanlı erişim (örn. webmail veya yönetim panelleri), **HAProxy** ile yük dengelemesi yapılarak iki sunucu arasında dağıtıldı.  
Bu sayede:
- Yüksek erişilebilirlik sağlandı.
- Trafiğin dengeli dağılımı garanti altına alındı.

## 🗄️ Veritabanı (DB) Mimarisi

**MariaDB** kullanılarak **Master-Master replikasyon** yapısı kuruldu.  
Avantajları:
- Her iki sunucuda da yazılabilir veritabanı.
- Sunucu arızasında veri kaybı olmadan devamlılık.

## 📂 Veri Eşitleme (ZFS)

Mail verileri ve yapılandırma dosyalarının senkronizasyonu için **ZFS dosya sistemi** kullanıldı.  
Bu sistem ile:
- Gerçek zamanlı eşitleme sağlandı.
- Dosya tutarlılığı ve yedeklilik elde edildi.



## 🔧 HAProxy Yapılandırması

İlk olarak Web arayüzünün yüksek erişilebilirliğini sağlamak için HAProxy yapılandırması yapılmalıdır.  
Bu sayede birincil (Primary) sunucuda **Nginx** veya **Apache** servislerinde bir problem oluştuğunda, istekler otomatik olarak ikincil (Secondary) sunucuya yönlendirilerek kesintisiz bir **Webmail** hizmeti sağlanır.

Aşağıda örnek bir HAProxy konfigürasyonu verilmiştir:

```haproxy
frontend webmail_https
    bind *:443 ssl crt /etc/haproxy/certs/test.com.pem
    mode http
    default_backend webmail_back

backend webmail_back
    mode http
    option httpchk GET /
    default-server inter 3s fall 3 rise 2

    server webmail1 192.168.1.10:443 ssl verify none check
    server webmail2 192.168.1.10:443 ssl verify none check backup
```

### 🧩 Yapılandırmaya Ait Açıklamalar:

- `frontend webmail_https`: Gelen HTTPS bağlantılarını karşılayan ön uç (frontend) tanımıdır.
- `bind *:443 ssl crt /etc/haproxy/certs/test.com.pem`: 443 numaralı port üzerinden SSL sertifikası ile bağlantı kabul edilir. Sertifika dosyası burada belirtilmiştir.
- `mode http`: HAProxy'nin HTTP modunda çalışmasını sağlar.
- `default_backend webmail_back`: Tüm HTTPS trafiği `webmail_back` adlı arka uca yönlendirilir.

---

- `backend webmail_back`: Webmail için yönlendirme yapılacak sunucular bu kısımda tanımlanır.
- `option httpchk GET /`: HAProxy, belirli aralıklarla `/` yoluna GET isteği atarak sunucunun çalışıp çalışmadığını kontrol eder.
- `default-server inter 3s fall 3 rise 2`:
  - `inter 3s`: Her 3 saniyede bir sağlık kontrolü yapılır.
  - `fall 3`: Bir sunucu 3 ardışık başarısız yanıt verirse "çalışmıyor" kabul edilir.
  - `rise 2`: 2 ardışık başarılı yanıt sonrasında sunucu tekrar "çalışır" olarak işaretlenir.

---

- `server webmail1 192.168.1.10:443 ssl verify none check`:  
  Birincil (aktif) webmail sunucusunun IP adresi belirtilmiştir. SSL kontrolü yapılmaz, sağlık kontrolü aktiftir.

- `server webmail2 192.168.1.10:443 ssl verify none check backup`:  
  İkincil (yedek) webmail sunucusudur. `backup` etiketi sayesinde sadece birincil sunucu erişilemez hale geldiğinde devreye girer.

> 🔄 Not: IP adresleri örnek olarak verilmiştir. Kendi altyapınıza göre güncellemeniz gerekmektedir.



## 📬 Mail Gateway Yapılandırması (Opsiyonel)

Mail sunucularımız için bir **Mail Gateway** kullanmak, güvenlik ve kararlılık açısından her zaman daha sağlıklıdır.  
Bu sayede saldırganlar, doğrudan mail sunucunuza zararlı dosyalar veya oltalama (phishing) mailleri gönderemez.  
Mail Gateway yapılandırması **opsiyoneldir**. Dilerseniz aşağıdaki örnekteki gibi **MX kayıtları** tanımlayarak da bu yapıyı kurabilirsiniz:

```dns
@ IN MX (10) mail.test.com
@ IN MX (20) backupmail.test.com
```

> 📌 DNS kaydınızda belirlemiş olduğunuz öncelik değerine göre mail iletimi sağlanır.  
> Örneğin; birincil sunucuda sorun yaşanırsa, gönderilen e-postalar ikinci öncelikli sunucuya yönlendirilir.

---

Ben bu yapılandırmada **Proxmox Mail Gateway (PMG)** kullanmaktayım.  
Aşağıda paylaştığım yapılandırma, **Postfix** tabanlı sistemler için uygundur.  
Eğer farklı bir **SMTP** sunucusu kullanıyorsanız, yapılandırmayı ona göre uyarlamanız gerekir.

```postfix
relay_transport = smtp:192.168.1.10:25
smtp_fallback_relay = [192.168.1.11]:25
soft_bounce = yes
bounce_queue_lifetime = 1h
```

### ⚙️ Açıklamalar:

- `relay_transport = smtp:192.168.1.10:25`:  
  Gelen maillerin ilk olarak bu IP adresindeki SMTP sunucusuna yönlendirilmesini sağlar.

- `smtp_fallback_relay = [192.168.1.11]:25`:  
  Eğer birincil sunucu (192.168.1.10) çalışmazsa, e-postalar bu IP'ye sahip yedek sunucuya yönlendirilir.

- `soft_bounce = yes`:  
  Geçici teslim hatalarında, mesajın tamamen reddedilmesini engeller.

- `bounce_queue_lifetime = 1h`:  
  Teslim edilemeyen maillerin kuyrukta ne kadar süre tutulacağını belirler (örneğin 1 saat).

> 🔄 Bu yapılandırma sayesinde, gateway üzerinden hem yedeklilik sağlanmış olur hem de daha güvenli bir mail sistemi elde edilir.



## 🛠️ MariaDB Master-Master Replikasyon

Bu sistemde **MariaDB** veritabanı kullanılmakta olup, **Master-Master replikasyon** yöntemi tercih edilmiştir.  
MariaDB'ye ait yapılandırma dosyalarına bu repoda ulaşabilirsiniz.

---

### 🔹 1. Adım: Primary Sunucuda Yapılacaklar

İlk olarak **primary** sunucunuza bağlanın ve MySQL oturumunu başlatın:

```sql
CREATE USER 'replicator'@'%' IDENTIFIED BY '12345678';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
SHOW MASTER STATUS;
```

Örnek çıktı:

```text
+--------------------+----------+----------------------------------------------+-------------------------------+
| File               | Position | Binlog_Do_DB                                 | Binlog_Ignore_DB              |
+--------------------+----------+----------------------------------------------+-------------------------------+
| mariadb-bin.000001 |      245 | amavisd,iredadmin,iredapd,roundcubemail,sogo | test,information_schema,mysql |
+--------------------+----------+----------------------------------------------+-------------------------------+
```

> ℹ️ `File` ve `Position` alanları, replikasyonun nereye kadar senkronize edileceğini gösterir. Bu değerleri **secondary sunucuda** kullanacağız.

---

### 🔹 2. Adım: Secondary Sunucuda Yapılacaklar

Secondary sunucuya geçin ve aşağıdaki komutları çalıştırın:

```sql
CREATE USER 'replicator'@'%' IDENTIFIED BY '12345678';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';

STOP SLAVE;
CHANGE MASTER TO 
    MASTER_HOST='192.168.1.10',
    MASTER_USER='replicator',
    MASTER_PASSWORD='12345678',
    MASTER_LOG_FILE='mariadb-bin.000001',
    MASTER_LOG_POS=245;

START SLAVE;
SHOW MASTER STATUS;
SHOW SLAVE STATUS\G;
```

> 📌 `MASTER_LOG_FILE` ve `MASTER_LOG_POS` değerlerini **primary sunucudaki** çıktıya göre doldurun.

Sunucuyu yeniden başlatın:

```bash
systemctl restart mariadb
```

---

### 🔹 3. Adım: Primary Sunucuyu Secondary’ye Bağlamak

Şimdi tekrar **primary** sunucuya dönüp replikasyonu ters yönde yapılandırıyoruz:

```sql
STOP SLAVE;
CHANGE MASTER TO 
    MASTER_HOST='192.168.1.11',
    MASTER_USER='replicator',
    MASTER_PASSWORD='12345678',
    MASTER_LOG_FILE='mariadb-bin.000001',
    MASTER_LOG_POS=289;

START SLAVE;
SHOW SLAVE STATUS\G;
```

> 📌 `MASTER_LOG_POS` değeri **secondary sunucunun** `SHOW MASTER STATUS` çıktısına göre ayarlanmalıdır.

MariaDB servisini yeniden başlatın:

```bash
systemctl restart mariadb
```

---

### ✅ Test Etme

Herhangi bir posta sunucusundan **RoundcubeMail** arayüzü ile giriş yaparak test edin.  
Daha sonra `roundcubemail -> users` tablosunu her iki sunucuda da kontrol edin.  
Değişiklikler başarılı bir şekilde senkronize olduysa yapılandırma doğru yapılmış demektir.

> 🔁 Artık iki sunucu arasında veri karşılıklı olarak eşitlenmektedir.







