# 🧩 API‑Driven Infrastructure  
**Orchestration de services AWS via API Gateway et Lambda (LocalStack + GitHub Codespaces)**

---

## ⚡ L’idée en 30 secondes

Cet atelier propose de concevoir une **architecture API‑driven** dans laquelle une **requête HTTP** déclenche, via **API Gateway** et une **fonction Lambda**, des **actions d’infrastructure sur des instances EC2**.

L’ensemble est exécuté :
- dans un **environnement AWS simulé avec LocalStack**
- **sans console graphique**
- directement depuis **GitHub Codespaces**

🎯 Objectif : comprendre comment des services **serverless** peuvent piloter dynamiquement des ressources d’infrastructure par API.

---

## 🧠 Notions clés à retenir

- **API Gateway** : point d’entrée HTTP
- **Lambda** : logique exécutée à la demande
- **EC2** : ressource d’infrastructure pilotée par API
- **API‑Driven Infrastructure** : l’infrastructure devient programmable

---

## 🏗️ Architecture cible

```
Client HTTP (curl)
        |
        v
API Gateway
        |
        v
Lambda
        |
        v
EC2 (start / stop)
```

---

## 🧩 Séquence 1 — GitHub Codespaces

### 🎯 Objectif
Créer un environnement de travail isolé et prêt à l’emploi.

### ⏱️ Difficulté
Très facile (~5 minutes)

### 🛠️ Étapes

1. Fork du repository Github : https://github.com/dceleste35/API_Driven
1. Aller sur votre repository GitHub (fork du projet API‑Driven)
2. Clic droit sur le bouton **Code**
3. Sélectionner **Open with Codespaces**
4. Cliquer sur **Create new Codespace**

👉 Le Codespace est maintenant connecté à votre repository.

---

## 🧩 Séquence 2 — Création de l’environnement AWS simulé (LocalStack)

### 🎯 Objectif
Créer un environnement AWS local simulé avec LocalStack.

### ⏱️ Difficulté
Simple (~5 minutes)

---

## 🔧 Installation de LocalStack

Dans le terminal du Codespace, exécuter **pas à pas** les commandes suivantes :

```bash
sudo -i mkdir rep_localstack
sudo -i python3 -m venv ./rep_localstack
sudo -i pip install --upgrade pip && python3 -m pip install localstack
export S3_SKIP_SIGNATURE_VALIDATION=0
localstack start -d
```

---

## 🔍 Vérification des services LocalStack

```bash
localstack status services
```

👉 Les services doivent apparaître comme **available**.
La sortie available indique que les services AWS sont correctement exposés par LocalStack et prêts à être utilisés. Les services ne consomment des ressources que lorsqu’ils sont appelés.


---

## 🌐 Récupération de l’endpoint AWS LocalStack

1. Aller dans l’onglet **PORTS** du Codespace
2. Repérer le port **4566**
3. Passer sa visibilité en **Public** ( Clique droit -> Visibilité du Port )
4. Ouvrir l’URL associée

👉 Cette URL correspond à votre **AWS_ENDPOINT LocalStack**

⚠️ Il est normal que le navigateur affiche une page vide :  
il s’agit d’une **API AWS**, pas d’une application web.

📌 **Conservez précieusement cette URL**, elle sera utilisée pour toutes les requêtes AWS.

---

## 🧠 Capitalisation (Séquence 2)

À l’issue de cette séquence, vous avez appris à :
- installer LocalStack dans GitHub Codespaces
- lancer un environnement AWS simulé
- exposer et récupérer un endpoint AWS local

---

## 🧪 Exercice — Piloter une instance EC2 via une API HTTP

### 🎯 Objectif
Mettre en place et utiliser une **API HTTP** déclenchant une **Lambda**, afin de **démarrer ou arrêter une instance EC2** dans un environnement AWS simulé avec **LocalStack**, sans interface graphique.

À la fin de l’exercice, vous devez démontrer qu’un **appel HTTP** modifie bien l’état d’une instance EC2 (`stopped` ↔ `running`).

---

## ✅ Pré‑requis de l’exercice

### 1️⃣ Vérifier que LocalStack est lancé
```bash
localstack status services
```

✔️ Les services `apigateway`, `lambda` et `ec2` doivent être indiqués comme **available**.

---

### 2️⃣ Récupérer l’endpoint AWS LocalStack

Dans GitHub Codespaces :
1. Ouvrir l’onglet **PORTS**
2. Repérer le port **4566**
3. Passer sa visibilité en **Public**
4. Copier l’URL associée

## 🔧 Installation de l’AWS CLI

GitHub Codespaces ne fournit pas AWS CLI par défaut.  
Avant de continuer, vous devez installer l’outil `aws`.

### Installation via apt (recommandée)

```bash
sudo apt update
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

Vérifier l’installation :
```bash
aws --version
```

Résultat attendu :
```
aws-cli/2.x.x Python/3.x ...
```

## 🧩 (Optionnel mais propre) Installer `awslocal`

## 🔧 Installation de awslocal (optionnel)

`awslocal` est un wrapper simplifiant l’utilisation de LocalStack.

```bash
pip install awscli-local
```

Vérifier :
```bash
awslocal --version
```

Exporter l’endpoint :
```bash
export AWS_ENDPOINT="https://<URL_DU_PORT_4566>"
```

AWS Crédential par défaut : 
```bash
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_SESSION_TOKEN=test
```


Vérifier que l’endpoint répond :
```bash
curl -s "$AWS_ENDPOINT/_localstack/health" | head
```

---

## 🧩 Étape A — Préparer l’outil AWS CLI

Tester si `awslocal` est disponible :
```bash
awslocal --version
```

Si la commande échoue, utiliser AWS CLI avec l’endpoint LocalStack.

Créer un alias (recommandé) :
```bash
alias awsls='aws --endpoint-url="$AWS_ENDPOINT"'
```

---

## 🧩 Étape B — Vérifier ou créer une instance EC2

### 1️⃣ Vérifier l’existence d’une instance
```bash
awsls ec2 describe-instances \
  --query "Reservations[].Instances[].InstanceId" \
  --output text
```

- Si un `InstanceId` apparaît → passer à l’étape C  
- Sinon → créer une instance

---

### 2️⃣ Créer une instance EC2 de test
```bash
awsls ec2 run-instances \
  --image-id ami-12345678 \
  --count 1 \
  --instance-type t2.micro
```

Récupérer l’ID de l’instance :
```bash
export INSTANCE_ID=$(awsls ec2 describe-instances \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text)

echo "INSTANCE_ID=$INSTANCE_ID"
```

Vérifier l’état initial :
```bash
awsls ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text
```

---

## 🧩 Étape C — Déployer l’API (API Gateway + Lambda)

Le repository fournit une commande de déploiement.  

```bash
make deploy
```

Aucune erreur bloquante ne doit apparaître.

---

## 🧩 Étape D — Récupérer l’URL de l’API Gateway

Lister les APIs disponibles :
```bash
awsls apigateway get-rest-apis \
  --query "items[].{id:id,name:name}" \
  --output table
```

Exporter l’ID de l’API utilisée :
```bash
export REST_API_ID="<ID_DE_L_API>"
```

Construire l’URL finale :
```bash
export API_URL="$AWS_ENDPOINT/restapis/$REST_API_ID/dev/_user_request_"
echo "$API_URL"
```

Tester l’API :
```bash
curl -i "$API_URL"
```

---

## 🧩 Étape E — Utiliser l’API pour piloter EC2

### 🔌 Spécification de l’API

**Endpoint**
```
POST /ec2
```

**Body JSON**
```json
{ "action": "stop", "instanceId": "i-xxxx" }
```

ou

```json
{ "action": "start", "instanceId": "i-xxxx" }
```

---

### ▶️ Arrêter l’instance EC2

```bash
curl -s -X POST "$API_URL/ec2" \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"stop\",\"instanceId\":\"$INSTANCE_ID\"}" | cat
```

Vérifier l’état :
```bash
awsls ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text
```

Résultat attendu :
```
stopped
```

---

### ▶️ Démarrer l’instance EC2

```bash
curl -s -X POST "$API_URL/ec2" \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"start\",\"instanceId\":\"$INSTANCE_ID\"}" | cat
```

Vérifier l’état :
```bash
awsls ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text
```

Résultat attendu :
```
running
```

---

## ✅ Validation attendue

Vous devez être capable de fournir :
- la commande HTTP utilisée pour arrêter l’instance
- la commande HTTP utilisée pour la démarrer
- une preuve du changement d’état EC2

---

## 🧾 Auto‑évaluation

- [ ] LocalStack lancé
- [ ] Endpoint AWS configuré
- [ ] Instance EC2 créée
- [ ] API déployée
- [ ] Appel HTTP stop fonctionnel
- [ ] Appel HTTP start fonctionnel

---

## 🧹 Nettoyage

```bash
localstack stop
```

---

## 🎓 Conclusion

Cet exercice démontre qu’une **architecture serverless API‑driven** permet de piloter dynamiquement des ressources d’infrastructure via de simples requêtes HTTP, sans dépendre d’une console graphique.
